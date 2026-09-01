/*
    Cho phép số lượng và tồn kho có tối đa 3 chữ số thập phân.
    Idempotent: có thể chạy lại an toàn trên dữ liệu hiện có.
*/
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @RecreateOriginalOrderItemIndex BIT = 0;
    IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.order_items')
             AND name = N'IX_order_items_original_order_item'
       )
    BEGIN
        SET @RecreateOriginalOrderItemIndex = 1;
        DROP INDEX IX_order_items_original_order_item ON dbo.order_items;
    END;

    DECLARE @QuantityColumns TABLE
    (
        table_name SYSNAME NOT NULL,
        column_name SYSNAME NOT NULL,
        nullability NVARCHAR(8) NOT NULL
    );

    INSERT INTO @QuantityColumns(table_name, column_name, nullability)
    VALUES
        (N'products', N'stock', N'NULL'),
        (N'order_items', N'quantity', N'NOT NULL'),
        (N'order_items', N'stock_before', N'NULL'),
        (N'order_items', N'stock_after', N'NULL'),
        (N'import_details', N'quantity', N'NULL'),
        (N'purchase_return_details', N'quantity', N'NOT NULL'),
        (N'inventory_check_details', N'system_stock', N'NOT NULL'),
        (N'inventory_check_details', N'actual_stock', N'NOT NULL'),
        (N'inventory_check_details', N'difference', N'NOT NULL');

    DECLARE
        @TableName SYSNAME,
        @ColumnName SYSNAME,
        @Nullability NVARCHAR(8),
        @ObjectId INT,
        @DefaultName SYSNAME,
        @DefaultDefinition NVARCHAR(MAX),
        @Sql NVARCHAR(MAX);

    DECLARE quantity_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_name, column_name, nullability
        FROM @QuantityColumns;

    OPEN quantity_cursor;
    FETCH NEXT FROM quantity_cursor INTO @TableName, @ColumnName, @Nullability;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ObjectId = OBJECT_ID(N'dbo.' + @TableName, N'U');

        IF @ObjectId IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM sys.columns
               WHERE object_id = @ObjectId
                 AND name = @ColumnName
                 AND (TYPE_NAME(user_type_id) <> N'decimal' OR precision <> 18 OR scale <> 3)
           )
        BEGIN
            SET @DefaultName = NULL;
            SET @DefaultDefinition = NULL;

            SELECT
                @DefaultName = dc.name,
                @DefaultDefinition = dc.definition
            FROM sys.default_constraints dc
            INNER JOIN sys.columns c
                ON c.object_id = dc.parent_object_id
               AND c.column_id = dc.parent_column_id
            WHERE dc.parent_object_id = @ObjectId
              AND c.name = @ColumnName;

            IF @DefaultName IS NOT NULL
            BEGIN
                SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
                    N' DROP CONSTRAINT ' + QUOTENAME(@DefaultName) + N';';
                EXEC sys.sp_executesql @Sql;
            END;

            SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
                N' ALTER COLUMN ' + QUOTENAME(@ColumnName) +
                N' DECIMAL(18,3) ' + @Nullability + N';';
            EXEC sys.sp_executesql @Sql;

            IF @DefaultName IS NOT NULL AND @DefaultDefinition IS NOT NULL
            BEGIN
                SET @Sql = N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
                    N' ADD CONSTRAINT ' + QUOTENAME(@DefaultName) +
                    N' DEFAULT ' + @DefaultDefinition + N' FOR ' + QUOTENAME(@ColumnName) + N';';
                EXEC sys.sp_executesql @Sql;
            END;
        END;

        FETCH NEXT FROM quantity_cursor INTO @TableName, @ColumnName, @Nullability;
    END;

    CLOSE quantity_cursor;
    DEALLOCATE quantity_cursor;

    IF @RecreateOriginalOrderItemIndex = 1
       AND NOT EXISTS
       (
           SELECT 1
           FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.order_items')
             AND name = N'IX_order_items_original_order_item'
       )
    BEGIN
        CREATE INDEX IX_order_items_original_order_item
            ON dbo.order_items(original_order_item_id, order_id)
            INCLUDE(base_quantity, quantity, gift_quantity);
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'quantity_cursor') >= 0
        CLOSE quantity_cursor;
    IF CURSOR_STATUS('local', 'quantity_cursor') > -3
        DEALLOCATE quantity_cursor;
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

CREATE OR ALTER PROCEDURE dbo.ImportDetails_Insert
    @ImportId INT,
    @ProductId INT,
    @Quantity DECIMAL(18,3),
    @ImportPrice DECIMAL(18,0)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.import_details(import_id, product_id, quantity, import_price, total)
    VALUES (@ImportId, @ProductId, @Quantity, @ImportPrice, @Quantity * @ImportPrice);
END;
GO

CREATE OR ALTER PROCEDURE dbo.InventoryCheckDetails_Insert
    @CheckId INT,
    @ProductId INT,
    @SystemStock DECIMAL(18,3),
    @ActualStock DECIMAL(18,3),
    @Reason NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Difference DECIMAL(18,3) = @ActualStock - @SystemStock;

    INSERT INTO dbo.inventory_check_details
        (check_id, product_id, system_stock, actual_stock, difference, reason)
    VALUES
        (@CheckId, @ProductId, @SystemStock, @ActualStock, @Difference, @Reason);

    UPDATE dbo.products SET stock = @ActualStock WHERE product_id = @ProductId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.OrderItems_Insert
    @OrderId INT,
    @ProductId INT,
    @Quantity DECIMAL(18,3),
    @UnitPrice DECIMAL(18,0),
    @OriginalPrice DECIMAL(18,0) = NULL,
    @CostPrice DECIMAL(18,0) = NULL,
    @ProductName NVARCHAR(250) = NULL,
    @Note NVARCHAR(250) = NULL,
    @WarrantyMonths INT = NULL,
    @SerialNumber NVARCHAR(500) = NULL,
    @WarrantyEndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FinalCostPrice DECIMAL(18,0);
    DECLARE @FinalOriginalPrice DECIMAL(18,0);

    SELECT
        @FinalCostPrice = ISNULL(import_price, 0),
        @FinalOriginalPrice = ISNULL(sell_price, @UnitPrice)
    FROM dbo.products
    WHERE product_id = @ProductId;

    SET @FinalCostPrice = ISNULL(NULLIF(@CostPrice, 0), ISNULL(@FinalCostPrice, 0));
    SET @FinalOriginalPrice = ISNULL(NULLIF(@OriginalPrice, 0), ISNULL(@FinalOriginalPrice, @UnitPrice));

    INSERT INTO dbo.order_items
        (order_id, product_id, quantity, unit_price, original_price, cost_price,
         product_name, note, warranty_months, serial_number, warranty_end_date)
    VALUES
        (@OrderId, @ProductId, @Quantity, @UnitPrice, @FinalOriginalPrice, @FinalCostPrice,
         @ProductName, @Note, @WarrantyMonths, @SerialNumber, @WarrantyEndDate);

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END;
GO

CREATE OR ALTER PROCEDURE dbo.OrderItems_UpdateQuantity
    @OrderItemId INT,
    @NewQuantity DECIMAL(18,3)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.order_items SET quantity = @NewQuantity WHERE order_item_id = @OrderItemId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.Product_IncreaseStock
    @ProductId INT,
    @Quantity DECIMAL(18,3),
    @NewImportPrice DECIMAL(18,0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(@Quantity, 0) <= 0 RETURN;

    IF ISNULL(@NewImportPrice, 0) <= 0
    BEGIN
        UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
        SET stock = ISNULL(stock, 0) + @Quantity
        WHERE product_id = @ProductId;
        IF @@ROWCOUNT = 0
            RAISERROR(N'Khong tim thay san pham de cap nhat ton kho.', 16, 1);
        RETURN;
    END;

    DECLARE @ImportPriceMethod INT = 1;
    SELECT TOP 1 @ImportPriceMethod = ISNULL(import_price_method, 1) FROM dbo.StoreInfo;
    IF @ImportPriceMethod NOT IN (1, 2) SET @ImportPriceMethod = 1;

    UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
    SET import_price = CASE
            WHEN @ImportPriceMethod = 2 THEN @NewImportPrice
            WHEN ISNULL(stock, 0) <= 0 THEN @NewImportPrice
            ELSE ((ISNULL(stock, 0) * ISNULL(import_price, 0)) + (@Quantity * @NewImportPrice))
                 / NULLIF(ISNULL(stock, 0) + @Quantity, 0)
        END,
        stock = ISNULL(stock, 0) + @Quantity
    WHERE product_id = @ProductId;

    IF @@ROWCOUNT = 0
        RAISERROR(N'Khong tim thay san pham de cap nhat ton kho.', 16, 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.Product_ReduceStock
    @ProductId INT,
    @Quantity DECIMAL(18,3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(@Quantity, 0) <= 0 RETURN;

    UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
    SET stock = ISNULL(stock, 0) - @Quantity
    WHERE product_id = @ProductId
      AND ISNULL(stock, 0) >= @Quantity;

    IF @@ROWCOUNT = 0
        RAISERROR(N'Khong du ton kho hoac khong tim thay san pham.', 16, 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.Product_UpdateStockOnly
    @ProductId INT,
    @Quantity DECIMAL(18,3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
    SET stock = ISNULL(stock, 0) + ISNULL(@Quantity, 0)
    WHERE product_id = @ProductId;

    IF @@ROWCOUNT = 0
        RAISERROR(N'Khong tim thay san pham de cap nhat ton kho.', 16, 1);
END;
GO

CREATE OR ALTER PROCEDURE dbo.Products_Insert
    @ProductCode NVARCHAR(50),
    @ProductName NVARCHAR(150),
    @CategoryId INT,
    @UnitId INT,
    @SellPrice DECIMAL(12,2),
    @ImportPrice DECIMAL(18,0),
    @Stock DECIMAL(18,3),
    @IsActive BIT,
    @WarrantyMonths INT,
    @HasSerial BIT,
    @ImagePath NVARCHAR(500),
    @Barcode NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), N'');

    INSERT INTO dbo.products
        (product_code, barcode, product_name, category_id, unit_id, sell_price,
         import_price, stock, is_active, created_at, warranty_months, has_serial, image_path)
    VALUES
        (@ProductCode, @Barcode, @ProductName, @CategoryId, @UnitId, @SellPrice,
         @ImportPrice, @Stock, @IsActive, GETDATE(), @WarrantyMonths, @HasSerial, @ImagePath);

    SELECT SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE dbo.Products_Update
    @ProductId INT,
    @ProductCode NVARCHAR(50),
    @ProductName NVARCHAR(150),
    @CategoryId INT,
    @UnitId INT,
    @SellPrice DECIMAL(12,2),
    @ImportPrice DECIMAL(18,0),
    @Stock DECIMAL(18,3),
    @IsActive BIT,
    @WarrantyMonths INT,
    @HasSerial BIT,
    @ImagePath NVARCHAR(500),
    @Barcode NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), N'');

    UPDATE dbo.products
    SET product_code = @ProductCode,
        barcode = @Barcode,
        product_name = @ProductName,
        category_id = @CategoryId,
        unit_id = @UnitId,
        sell_price = @SellPrice,
        import_price = @ImportPrice,
        stock = @Stock,
        is_active = @IsActive,
        warranty_months = @WarrantyMonths,
        has_serial = @HasSerial,
        image_path = @ImagePath
    WHERE product_id = @ProductId;
END;
GO

SELECT
    target.table_name AS TableName,
    target.column_name AS ColumnName,
    TYPE_NAME(col.user_type_id) AS DataType,
    col.precision AS [Precision],
    col.scale AS Scale,
    CASE
        WHEN TYPE_NAME(col.user_type_id) = N'decimal' AND col.precision = 18 AND col.scale = 3
            THEN N'OK'
        ELSE N'CHƯA ĐẠT'
    END AS MigrationStatus
FROM
(
    VALUES
        (N'products', N'stock'),
        (N'order_items', N'quantity'),
        (N'order_items', N'stock_before'),
        (N'order_items', N'stock_after'),
        (N'import_details', N'quantity'),
        (N'purchase_return_details', N'quantity'),
        (N'inventory_check_details', N'system_stock'),
        (N'inventory_check_details', N'actual_stock'),
        (N'inventory_check_details', N'difference')
) target(table_name, column_name)
LEFT JOIN sys.tables tbl
    ON tbl.name = target.table_name AND SCHEMA_NAME(tbl.schema_id) = N'dbo'
LEFT JOIN sys.columns col
    ON col.object_id = tbl.object_id AND col.name = target.column_name
ORDER BY target.table_name, target.column_name;
GO
