SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Apply only after every LAN workstation has been upgraded to the application
-- version that uses Product.SaveProduct and Order.CancelWithStockRestore.
-- This migration intentionally aborts before changing anything when legacy
-- duplicates/null keys must be reviewed by an operator.
BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.product_serials', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'serial_number') IS NULL
        THROW 51280, N'Thiếu cấu trúc product_serials.serial_number.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.product_serials
        WHERE NULLIF(LTRIM(RTRIM(serial_number)), N'') IS NOT NULL
        GROUP BY LTRIM(RTRIM(serial_number))
        HAVING COUNT_BIG(*) > 1
    )
        THROW 51281, N'Đang có Serial/IMEI trùng sau khi chuẩn hóa. Chưa có thay đổi nào được áp dụng.', 1;

    -- All application writers already trim new values. Normalize existing rows
    -- only after the duplicate preflight has passed, then let SQL enforce it.
    UPDATE dbo.product_serials
    SET serial_number = NULLIF(LTRIM(RTRIM(serial_number)), N'')
    WHERE serial_number IS NOT NULL
      AND
      (
          NULLIF(LTRIM(RTRIM(serial_number)), N'') IS NULL
          OR DATALENGTH(serial_number) <> DATALENGTH(LTRIM(RTRIM(serial_number)))
      );

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic
            ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal = 1
        INNER JOIN sys.columns c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.product_serials')
          AND i.is_unique = 1
          AND i.is_disabled = 0
          AND i.is_hypothetical = 0
          AND c.name = N'serial_number'
          AND NOT EXISTS
          (
              SELECT 1
              FROM sys.index_columns extra
              WHERE extra.object_id = i.object_id
                AND extra.index_id = i.index_id
                AND extra.key_ordinal > 1
          )
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.product_serials')
              AND name = N'UX_product_serials_serial_number'
        )
            THROW 51282, N'Index UX_product_serials_serial_number đã tồn tại nhưng không bảo đảm duy nhất toàn hệ thống.', 1;

        CREATE UNIQUE INDEX UX_product_serials_serial_number
            ON dbo.product_serials(serial_number)
            WHERE serial_number IS NOT NULL;
    END;

    IF OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NULL
       OR COL_LENGTH(N'dbo.inventory_check_details', N'check_id') IS NULL
       OR COL_LENGTH(N'dbo.inventory_check_details', N'product_id') IS NULL
        THROW 51283, N'Thiếu cấu trúc chi tiết kiểm kho.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.inventory_check_details
        WHERE check_id IS NULL OR product_id IS NULL
    )
        THROW 51284, N'Chi tiết kiểm kho đang có check_id hoặc product_id rỗng. Chưa có thay đổi nào được áp dụng.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.inventory_check_details
        GROUP BY check_id, product_id
        HAVING COUNT_BIG(*) > 1
    )
        THROW 51285, N'Một phiếu kiểm kho đang có sản phẩm trùng dòng. Chưa có thay đổi nào được áp dụng.', 1;

    ALTER TABLE dbo.inventory_check_details ALTER COLUMN check_id INT NOT NULL;
    ALTER TABLE dbo.inventory_check_details ALTER COLUMN product_id INT NOT NULL;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns first_key
            ON first_key.object_id = i.object_id AND first_key.index_id = i.index_id AND first_key.key_ordinal = 1
        INNER JOIN sys.columns first_column
            ON first_column.object_id = first_key.object_id AND first_column.column_id = first_key.column_id
        INNER JOIN sys.index_columns second_key
            ON second_key.object_id = i.object_id AND second_key.index_id = i.index_id AND second_key.key_ordinal = 2
        INNER JOIN sys.columns second_column
            ON second_column.object_id = second_key.object_id AND second_column.column_id = second_key.column_id
        WHERE i.object_id = OBJECT_ID(N'dbo.inventory_check_details')
          AND i.is_unique = 1
          AND i.is_disabled = 0
          AND i.is_hypothetical = 0
          AND first_column.name = N'check_id'
          AND second_column.name = N'product_id'
          AND NOT EXISTS
          (
              SELECT 1
              FROM sys.index_columns extra
              WHERE extra.object_id = i.object_id
                AND extra.index_id = i.index_id
                AND extra.key_ordinal > 2
          )
    )
    BEGIN
        IF EXISTS
        (
            SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'dbo.inventory_check_details')
              AND name = N'UX_inventory_check_details_check_product'
        )
            THROW 51286, N'Index UX_inventory_check_details_check_product đã tồn tại nhưng không phù hợp.', 1;

        CREATE UNIQUE INDEX UX_inventory_check_details_check_product
            ON dbo.inventory_check_details(check_id, product_id);
    END;

    -- Retire bypasses that write aggregate stock or cancel an order without the
    -- current variant/batch/serial transaction. Signatures are preserved so an
    -- old client receives an explicit upgrade error instead of a binding error.
    IF OBJECT_ID(N'dbo.Products_Insert') IS NOT NULL AND OBJECT_ID(N'dbo.Products_Insert', N'P') IS NULL
        THROW 51287, N'dbo.Products_Insert không phải stored procedure.', 1;
    IF OBJECT_ID(N'dbo.Products_Update') IS NOT NULL AND OBJECT_ID(N'dbo.Products_Update', N'P') IS NULL
        THROW 51287, N'dbo.Products_Update không phải stored procedure.', 1;
    IF OBJECT_ID(N'dbo.Product_IncreaseStock') IS NOT NULL AND OBJECT_ID(N'dbo.Product_IncreaseStock', N'P') IS NULL
        THROW 51287, N'dbo.Product_IncreaseStock không phải stored procedure.', 1;
    IF OBJECT_ID(N'dbo.Product_ReduceStock') IS NOT NULL AND OBJECT_ID(N'dbo.Product_ReduceStock', N'P') IS NULL
        THROW 51287, N'dbo.Product_ReduceStock không phải stored procedure.', 1;
    IF OBJECT_ID(N'dbo.Product_UpdateStockOnly') IS NOT NULL AND OBJECT_ID(N'dbo.Product_UpdateStockOnly', N'P') IS NULL
        THROW 51287, N'dbo.Product_UpdateStockOnly không phải stored procedure.', 1;
    IF OBJECT_ID(N'dbo.Orders_Cancel') IS NOT NULL AND OBJECT_ID(N'dbo.Orders_Cancel', N'P') IS NULL
        THROW 51287, N'dbo.Orders_Cancel không phải stored procedure.', 1;

    IF OBJECT_ID(N'dbo.Products_Insert', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Products_Insert
            @ProductCode NVARCHAR(50), @ProductName NVARCHAR(150), @CategoryId INT,
            @UnitId INT, @SellPrice DECIMAL(12,2), @ImportPrice DECIMAL(18,0),
            @Stock DECIMAL(18,3), @IsActive BIT, @WarrantyMonths INT,
            @HasSerial BIT, @ImagePath NVARCHAR(500), @Barcode NVARCHAR(100) = NULL
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51288, N''Luồng thêm sản phẩm cũ đã ngừng sử dụng. Vui lòng cập nhật MyShop.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.Products_Update', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Products_Update
            @ProductId INT, @ProductCode NVARCHAR(50), @ProductName NVARCHAR(150),
            @CategoryId INT, @UnitId INT, @SellPrice DECIMAL(12,2),
            @ImportPrice DECIMAL(18,0), @Stock DECIMAL(18,3), @IsActive BIT,
            @WarrantyMonths INT, @HasSerial BIT, @ImagePath NVARCHAR(500),
            @Barcode NVARCHAR(100) = NULL
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51288, N''Luồng cập nhật sản phẩm cũ đã ngừng sử dụng. Vui lòng cập nhật MyShop.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.Product_IncreaseStock', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Product_IncreaseStock
            @ProductId INT, @Quantity DECIMAL(18,3), @NewImportPrice DECIMAL(18,0)
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51289, N''Luồng tăng tồn cũ đã ngừng sử dụng. Hãy dùng phiếu nhập hoặc trả hàng.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.Product_ReduceStock', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Product_ReduceStock
            @ProductId INT, @Quantity DECIMAL(18,3)
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51289, N''Luồng giảm tồn cũ đã ngừng sử dụng. Hãy dùng bán hàng, trả hàng hoặc kiểm kho.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.Product_UpdateStockOnly', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Product_UpdateStockOnly
            @ProductId INT, @Quantity DECIMAL(18,3)
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51289, N''Luồng chỉnh tồn cũ đã ngừng sử dụng. Hãy dùng nghiệp vụ kho hiện hành.'', 1;
        END;');

    IF OBJECT_ID(N'dbo.Orders_Cancel', N'P') IS NOT NULL
        EXEC(N'ALTER PROCEDURE dbo.Orders_Cancel @OrderId INT
        AS
        BEGIN
            SET NOCOUNT ON;
            THROW 51290, N''Luồng hủy hóa đơn cũ đã ngừng sử dụng. Vui lòng cập nhật MyShop.'', 1;
        END;');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
