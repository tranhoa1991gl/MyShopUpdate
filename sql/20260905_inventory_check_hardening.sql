SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Retire only the legacy stocktake entry points. The updated application saves
-- the whole stocktake through InventoryCheck.SaveCheck in one transaction.
-- Apply alongside the new application on all workstations. No inventory data
-- changes; serial scrapping, history and reporting procedures remain available.
BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.InventoryCheck_Insert') IS NOT NULL
       AND OBJECT_ID(N'dbo.InventoryCheck_Insert', N'P') IS NULL
        THROW 51270, N'dbo.InventoryCheck_Insert không phải stored procedure.', 1;

    IF OBJECT_ID(N'dbo.InventoryCheckDetails_Insert') IS NOT NULL
       AND OBJECT_ID(N'dbo.InventoryCheckDetails_Insert', N'P') IS NULL
        THROW 51270, N'dbo.InventoryCheckDetails_Insert không phải stored procedure.', 1;

    IF OBJECT_ID(N'dbo.InventoryCheck_Insert', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.InventoryCheck_Insert
            @CheckCode VARCHAR(20), @EmployeeId INT, @Note NVARCHAR(MAX)
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51271, N''Luồng kiểm kê cũ đã ngừng sử dụng. Vui lòng cập nhật ứng dụng và chốt toàn bộ phiếu kiểm kê.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.InventoryCheckDetails_Insert', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.InventoryCheckDetails_Insert
            @CheckId INT, @ProductId INT, @SystemStock DECIMAL(18,3),
            @ActualStock DECIMAL(18,3), @Reason NVARCHAR(255)
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51271, N''Luồng kiểm kê cũ đã ngừng sử dụng. Vui lòng cập nhật ứng dụng và chốt toàn bộ phiếu kiểm kê.'', 1;
        END;');

    -- Supporting indexes keep locked tracking checks scoped by product.
    -- Existing enabled, unfiltered B-tree indexes with product_id as their first
    -- key already provide the required seek/range path and are kept unchanged.
    IF OBJECT_ID(N'dbo.product_serials', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'product_id') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'status') IS NULL
        THROW 51272, N'Thiếu cấu trúc product_serials để bảo vệ kiểm kho. Vui lòng cập nhật cơ sở dữ liệu trước.', 1;
    
    IF OBJECT_ID(N'dbo.product_variants', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'product_id') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'is_active') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'stock_base_qty') IS NULL
        THROW 51272, N'Thiếu cấu trúc product_variants để bảo vệ kiểm kho. Vui lòng cập nhật cơ sở dữ liệu trước.', 1;
    
    IF OBJECT_ID(N'dbo.product_batches', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_batches', N'product_id') IS NULL
       OR COL_LENGTH(N'dbo.product_batches', N'quantity_remaining') IS NULL
        THROW 51272, N'Thiếu cấu trúc product_batches để bảo vệ kiểm kho. Vui lòng cập nhật cơ sở dữ liệu trước.', 1;
    
    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.product_serials') AND i.type IN (1, 2)
          AND i.is_disabled = 0 AND i.is_hypothetical = 0 AND i.has_filter = 0
          AND ic.key_ordinal = 1 AND c.name = N'product_id'
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.product_serials') AND name = N'IX_product_serials_inventory_tracking'
        )
            THROW 51273, N'Index IX_product_serials_inventory_tracking đã tồn tại nhưng không phù hợp. Vui lòng kiểm tra trước khi cập nhật.', 1;
        CREATE INDEX IX_product_serials_inventory_tracking ON dbo.product_serials(product_id, status);
    END;
    
    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.product_variants') AND i.type IN (1, 2)
          AND i.is_disabled = 0 AND i.is_hypothetical = 0 AND i.has_filter = 0
          AND ic.key_ordinal = 1 AND c.name = N'product_id'
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.product_variants') AND name = N'IX_product_variants_inventory_tracking'
        )
            THROW 51273, N'Index IX_product_variants_inventory_tracking đã tồn tại nhưng không phù hợp. Vui lòng kiểm tra trước khi cập nhật.', 1;
        CREATE INDEX IX_product_variants_inventory_tracking ON dbo.product_variants(product_id) INCLUDE(is_active, stock_base_qty);
    END;
    
    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        INNER JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.product_batches') AND i.type IN (1, 2)
          AND i.is_disabled = 0 AND i.is_hypothetical = 0 AND i.has_filter = 0
          AND ic.key_ordinal = 1 AND c.name = N'product_id'
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.product_batches') AND name = N'IX_product_batches_inventory_tracking'
        )
            THROW 51273, N'Index IX_product_batches_inventory_tracking đã tồn tại nhưng không phù hợp. Vui lòng kiểm tra trước khi cập nhật.', 1;
        CREATE INDEX IX_product_batches_inventory_tracking ON dbo.product_batches(product_id) INCLUDE(quantity_remaining);
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
