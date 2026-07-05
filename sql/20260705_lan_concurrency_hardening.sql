IF COL_LENGTH(N'dbo.order_items', N'stock_before') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_before INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'stock_after') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_after INT NULL;
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_orders_order_code_not_null'
      AND object_id = OBJECT_ID(N'dbo.orders')
)
AND NOT EXISTS (
    SELECT 1
    FROM dbo.orders
    WHERE order_code IS NOT NULL
    GROUP BY order_code
    HAVING COUNT(*) > 1
)
BEGIN
    CREATE UNIQUE INDEX UX_orders_order_code_not_null
    ON dbo.orders(order_code)
    WHERE order_code IS NOT NULL;
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_imports_import_code_not_null'
      AND object_id = OBJECT_ID(N'dbo.imports')
)
AND NOT EXISTS (
    SELECT 1
    FROM dbo.imports
    WHERE import_code IS NOT NULL
    GROUP BY import_code
    HAVING COUNT(*) > 1
)
BEGIN
    CREATE UNIQUE INDEX UX_imports_import_code_not_null
    ON dbo.imports(import_code)
    WHERE import_code IS NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.Product_ReduceStock', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Product_ReduceStock;
GO

CREATE PROCEDURE dbo.Product_ReduceStock
    @ProductId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@Quantity, 0) <= 0
        RETURN;

    UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
    SET stock = ISNULL(stock, 0) - @Quantity
    WHERE product_id = @ProductId
      AND ISNULL(stock, 0) >= @Quantity;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR(N'Khong du ton kho hoac khong tim thay san pham.', 16, 1);
        RETURN;
    END
END
GO

IF OBJECT_ID(N'dbo.Product_IncreaseStock', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Product_IncreaseStock;
GO

CREATE PROCEDURE dbo.Product_IncreaseStock
    @ProductId INT,
    @Quantity INT,
    @NewImportPrice DECIMAL(18,0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@Quantity, 0) <= 0
        RETURN;

    IF ISNULL(@NewImportPrice, 0) <= 0
    BEGIN
        UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
        SET stock = ISNULL(stock, 0) + @Quantity
        WHERE product_id = @ProductId;

        IF @@ROWCOUNT = 0
            RAISERROR(N'Khong tim thay san pham de cap nhat ton kho.', 16, 1);

        RETURN;
    END

    DECLARE @ImportPriceMethod INT = 1;

    SELECT TOP 1
        @ImportPriceMethod = ISNULL(import_price_method, 1)
    FROM dbo.StoreInfo;

    IF @ImportPriceMethod NOT IN (1, 2)
        SET @ImportPriceMethod = 1;

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
END
GO

IF OBJECT_ID(N'dbo.Product_UpdateStockOnly', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Product_UpdateStockOnly;
GO

CREATE PROCEDURE dbo.Product_UpdateStockOnly
    @ProductId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE dbo.products WITH (UPDLOCK, ROWLOCK)
    SET stock = ISNULL(stock, 0) + ISNULL(@Quantity, 0)
    WHERE product_id = @ProductId;

    IF @@ROWCOUNT = 0
        RAISERROR(N'Khong tim thay san pham de cap nhat ton kho.', 16, 1);
END
GO

IF OBJECT_ID(N'dbo.ProductSerials_Sell', N'P') IS NOT NULL
    DROP PROCEDURE dbo.ProductSerials_Sell;
GO

CREATE PROCEDURE dbo.ProductSerials_Sell
    @serial_number NVARCHAR(100),
    @order_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');

    IF @serial_number IS NULL
    BEGIN
        RAISERROR(N'Serial/IMEI khong hop le.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials WITH (UPDLOCK, HOLDLOCK)
        WHERE serial_number = @serial_number
          AND order_id = @order_id
          AND status = 1
    )
        RETURN;

    UPDATE dbo.product_serials WITH (UPDLOCK, ROWLOCK)
    SET order_id = @order_id,
        status = 1
    WHERE serial_number = @serial_number
      AND status = 0;

    IF @@ROWCOUNT = 0
        RAISERROR(N'Serial/IMEI da duoc ban hoac khong con trong kho.', 16, 1);
END
GO

IF OBJECT_ID(N'dbo.Orders_Cancel', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Orders_Cancel;
GO

CREATE PROCEDURE dbo.Orders_Cancel
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(50);

    BEGIN TRANSACTION;

    BEGIN TRY
        SELECT @Status = status
        FROM dbo.orders WITH (UPDLOCK, HOLDLOCK)
        WHERE order_id = @OrderId;

        IF @Status IS NULL
        BEGIN
            RAISERROR(N'Khong tim thay hoa don can huy.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @Status = N'Cancelled'
        BEGIN
            RAISERROR(N'Hoa don nay da bi huy truoc do.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @Status IN (N'Completed', N'Paid', N'Partial')
        BEGIN
            UPDATE p
            SET p.stock = ISNULL(p.stock, 0) + ISNULL(oi.quantity, 0)
            FROM dbo.products p WITH (UPDLOCK, ROWLOCK)
            INNER JOIN dbo.order_items oi ON oi.product_id = p.product_id
            WHERE oi.order_id = @OrderId;
        END

        UPDATE dbo.product_serials
        SET status = 0,
            order_id = NULL
        WHERE order_id = @OrderId;

        UPDATE dbo.orders
        SET status = N'Cancelled'
        WHERE order_id = @OrderId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO
