CREATE OR ALTER PROCEDURE dbo.Report_GetOverview
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Tổng doanh thu theo kỳ lọc
    DECLARE @TotalSales DECIMAL(18,0);

    SELECT @TotalSales = SUM(final_amount)
    FROM orders
    WHERE order_date BETWEEN @FromDate AND @ToDate
      AND status IN ('Completed', 'Paid', 'Partial');

    -- 2. Tổng nhập hàng theo kỳ lọc
    DECLARE @TotalImport DECIMAL(18,0);

    SELECT @TotalImport = SUM(final_amount)
    FROM imports
    WHERE import_date BETWEEN @FromDate AND @ToDate
      AND status IN ('Completed', 'Paid', 'Partial');

    -- 3. Số đơn theo kỳ lọc
    DECLARE @CountOrders INT;

    SELECT @CountOrders = COUNT(*)
    FROM orders
    WHERE order_date BETWEEN @FromDate AND @ToDate
      AND status IN ('Completed', 'Paid', 'Partial');

    -- 4. Công nợ khách hàng hiện tại
    DECLARE @TotalDebtCustomer DECIMAL(18,0);

    SELECT @TotalDebtCustomer =
        ISNULL(SUM(final_amount - ISNULL(paid_amount, 0)), 0)
    FROM orders
    WHERE status IN ('Completed', 'Partial')
      AND final_amount > ISNULL(paid_amount, 0);

    -- 5. Công nợ nhà cung cấp hiện tại
    -- Phải trừ thêm các khoản chi sau nhập trong supplier_payments
    DECLARE @TotalDebtSupplier DECIMAL(18,0);

    SELECT @TotalDebtSupplier =
        ISNULL((
            SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
            FROM imports
            WHERE status != 'Cancelled'
        ), 0)
        -
        ISNULL((
            SELECT SUM(ISNULL(amount, 0))
            FROM supplier_payments
        ), 0);

    IF @TotalDebtSupplier < 0
        SET @TotalDebtSupplier = 0;

    SELECT
        ISNULL(@TotalSales, 0) AS TotalRevenue,
        ISNULL(@TotalImport, 0) AS TotalCost,
        ISNULL(@CountOrders, 0) AS OrderCount,
        ISNULL(@TotalSales, 0) - ISNULL(@TotalImport, 0) AS GrossProfit,
        ISNULL(@TotalDebtCustomer, 0) AS TotalDebtCustomer,
        ISNULL(@TotalDebtSupplier, 0) AS TotalDebtSupplier;
END
GO