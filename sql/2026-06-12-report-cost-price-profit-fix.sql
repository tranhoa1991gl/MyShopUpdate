/*
    MyShop - Fix gia von / loi nhuan gop
    MigrationId: 2026-06-12-report-cost-price-profit-fix

    Muc dich:
    - Cap nhat cost_price cho cac dong hoa don cu da luu 0/NULL.
    - Sua OrderItems_Insert de tu lay gia von tu products.import_price neu C# truyen 0/NULL.
    - Sua Report_GetOverview de tinh Gia von hang ban va Loi nhuan gop dung hon.
*/

IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.products', N'U') IS NOT NULL
BEGIN
    UPDATE oi
    SET oi.cost_price = ISNULL(p.import_price, 0)
    FROM dbo.order_items oi
    INNER JOIN dbo.products p ON p.product_id = oi.product_id
    WHERE ISNULL(oi.cost_price, 0) = 0
      AND ISNULL(p.import_price, 0) > 0;
END
GO

IF OBJECT_ID(N'dbo.OrderItems_Insert', N'P') IS NOT NULL
    DROP PROCEDURE dbo.OrderItems_Insert;
GO

CREATE PROCEDURE dbo.OrderItems_Insert
    @OrderId INT,
    @ProductId INT,
    @Quantity INT,
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

    INSERT INTO dbo.order_items (
        order_id,
        product_id,
        quantity,
        unit_price,
        original_price,
        cost_price,
        product_name,
        note,
        warranty_months,
        serial_number,
        warranty_end_date
    )
    VALUES (
        @OrderId,
        @ProductId,
        @Quantity,
        @UnitPrice,
        @FinalOriginalPrice,
        @FinalCostPrice,
        @ProductName,
        @Note,
        @WarrantyMonths,
        @SerialNumber,
        @WarrantyEndDate
    );
END
GO

IF OBJECT_ID(N'dbo.Report_GetOverview', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Report_GetOverview;
GO

CREATE PROCEDURE dbo.Report_GetOverview
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME = @FromDate;
    DECLARE @EndDate DATETIME = @ToDate;

    DECLARE @GrossSales DECIMAL(18,0) = 0;
    DECLARE @CustomerReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetRevenue DECIMAL(18,0) = 0;

    DECLARE @TotalPurchase DECIMAL(18,0) = 0;
    DECLARE @PurchaseReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetPurchase DECIMAL(18,0) = 0;

    DECLARE @OrderCount INT = 0;
    DECLARE @CostOfGoodsSold DECIMAL(18,0) = 0;
    DECLARE @GrossProfit DECIMAL(18,0) = 0;

    DECLARE @TotalDebtCustomer DECIMAL(18,0) = 0;
    DECLARE @TotalDebtSupplier DECIMAL(18,0) = 0;

    SELECT @GrossSales = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') <> N'RETURN';

    SELECT @CustomerReturnAmount = ISNULL(SUM(ABS(ISNULL(final_amount, 0))), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') = N'RETURN';

    SET @NetRevenue = ISNULL(@GrossSales, 0) - ISNULL(@CustomerReturnAmount, 0);
    IF @NetRevenue < 0 SET @NetRevenue = 0;

    SELECT @TotalPurchase = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.imports
    WHERE import_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
    BEGIN
        SELECT @PurchaseReturnAmount = ISNULL(SUM(ISNULL(total_amount, 0)), 0)
        FROM dbo.purchase_returns
        WHERE return_date BETWEEN @StartDate AND @EndDate
          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');
    END

    SET @NetPurchase = ISNULL(@TotalPurchase, 0) - ISNULL(@PurchaseReturnAmount, 0);
    IF @NetPurchase < 0 SET @NetPurchase = 0;

    SELECT @OrderCount = COUNT(*)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') <> N'RETURN';

    /*
        Gia von hang ban:
        - Uu tien order_items.cost_price vi day la gia von tai thoi diem ban.
        - Neu cost_price = 0/NULL thi fallback ve products.import_price.
        - Don tra hang khach (order_type = RETURN) se tru nguoc gia von.
    */
    SELECT @CostOfGoodsSold = ISNULL(SUM(
        CASE
            WHEN ISNULL(o.order_type, N'') = N'RETURN' THEN
                -1 * ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
            ELSE
                ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
        END
    ), 0)
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON o.order_id = oi.order_id
    LEFT JOIN dbo.products p ON p.product_id = oi.product_id
    WHERE o.order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(o.status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND oi.product_id IS NOT NULL;

    IF @CostOfGoodsSold < 0 SET @CostOfGoodsSold = 0;

    SET @GrossProfit = ISNULL(@NetRevenue, 0) - ISNULL(@CostOfGoodsSold, 0);

    SELECT @TotalDebtCustomer = ISNULL(SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0)), 0)
    FROM dbo.orders
    WHERE ISNULL(status, N'') IN (N'Completed', N'Partial')
      AND ISNULL(final_amount, 0) > ISNULL(paid_amount, 0)
      AND ISNULL(order_type, N'') <> N'RETURN';

    SELECT @TotalDebtSupplier =
        ISNULL((
            SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
            FROM dbo.imports
            WHERE ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0)
        -
        ISNULL((
            SELECT SUM(ISNULL(amount, 0))
            FROM dbo.supplier_payments
        ), 0);

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
    BEGIN
        SELECT @TotalDebtSupplier = @TotalDebtSupplier - ISNULL(SUM(ISNULL(total_amount, 0)), 0)
        FROM dbo.purchase_returns
        WHERE ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');
    END

    IF @TotalDebtSupplier < 0 SET @TotalDebtSupplier = 0;

    SELECT
        ISNULL(@NetRevenue, 0) AS TotalRevenue,
        ISNULL(@NetPurchase, 0) AS TotalCost,
        ISNULL(@OrderCount, 0) AS OrderCount,
        ISNULL(@GrossProfit, 0) AS GrossProfit,
        ISNULL(@TotalDebtCustomer, 0) AS TotalDebtCustomer,
        ISNULL(@TotalDebtSupplier, 0) AS TotalDebtSupplier,
        ISNULL(@GrossSales, 0) AS GrossSales,
        ISNULL(@CustomerReturnAmount, 0) AS CustomerReturnAmount,
        ISNULL(@TotalPurchase, 0) AS TotalPurchase,
        ISNULL(@PurchaseReturnAmount, 0) AS PurchaseReturnAmount,
        ISNULL(@CostOfGoodsSold, 0) AS CostOfGoodsSold;
END
GO
