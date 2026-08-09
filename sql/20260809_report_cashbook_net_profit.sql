/* Feature 2026-08-09
   Include manual cashbook income/expense in overview report.
   Safe to run after 20260809_cashbook_module.sql. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_categories
    ADD affects_profit BIT NOT NULL
        CONSTRAINT DF_cashbook_categories_affects_profit DEFAULT (1);
END
GO

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
BEGIN
    UPDATE dbo.cashbook_categories
    SET affects_profit = 0
    WHERE category_name IN (N'Góp vốn', N'Thu nợ khách hàng', N'Hoàn tiền nhà cung cấp', N'Chi trả nhà cung cấp');
END
GO

IF OBJECT_ID(N'dbo.Report_GetOverview', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Report_GetOverview @FromDate DATETIME, @ToDate DATETIME AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Report_GetOverview]
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

    DECLARE @CashbookIncome DECIMAL(18,0) = 0;
    DECLARE @CashbookExpense DECIMAL(18,0) = 0;
    DECLARE @NetProfitAfterCashbook DECIMAL(18,0) = 0;

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

    SELECT @PurchaseReturnAmount = ISNULL(SUM(ISNULL(total_amount, 0)), 0)
    FROM dbo.purchase_returns
    WHERE return_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');

    SET @NetPurchase = ISNULL(@TotalPurchase, 0) - ISNULL(@PurchaseReturnAmount, 0);
    IF @NetPurchase < 0 SET @NetPurchase = 0;

    SELECT @OrderCount = COUNT(*)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') <> N'RETURN';

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

    IF OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
    BEGIN
        DECLARE @CashbookSql NVARCHAR(MAX);

        SET @CashbookSql = N'
SELECT
    @IncomeOut = ISNULL(SUM(CASE WHEN e.entry_type = N''IN'' THEN e.amount ELSE 0 END), 0),
    @ExpenseOut = ISNULL(SUM(CASE WHEN e.entry_type = N''OUT'' THEN e.amount ELSE 0 END), 0)
FROM dbo.cashbook_entries e
LEFT JOIN dbo.cashbook_categories c ON c.category_id = e.category_id
WHERE e.is_deleted = 0
  AND e.entry_date BETWEEN @StartDateIn AND @EndDateIn
  AND ISNULL(c.affects_profit, 1) = 1;';

        EXEC sp_executesql
            @CashbookSql,
            N'@StartDateIn DATETIME, @EndDateIn DATETIME, @IncomeOut DECIMAL(18,0) OUTPUT, @ExpenseOut DECIMAL(18,0) OUTPUT',
            @StartDateIn = @StartDate,
            @EndDateIn = @EndDate,
            @IncomeOut = @CashbookIncome OUTPUT,
            @ExpenseOut = @CashbookExpense OUTPUT;
    END

    SET @NetProfitAfterCashbook =
        ISNULL(@GrossProfit, 0) + ISNULL(@CashbookIncome, 0) - ISNULL(@CashbookExpense, 0);

    SELECT @TotalDebtCustomer = ISNULL(SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0)), 0)
    FROM dbo.orders
    WHERE ISNULL(status, N'') IN (N'Completed', N'Partial')
      AND ISNULL(final_amount, 0) > ISNULL(paid_amount, 0)
      AND ISNULL(order_type, N'') <> N'RETURN';

    SELECT @TotalDebtSupplier = ISNULL(SUM(
        CASE
            WHEN ISNULL(d.ImportDebt, 0) - ISNULL(paid.TotalPaid, 0) > 0
                THEN ISNULL(d.ImportDebt, 0) - ISNULL(paid.TotalPaid, 0)
            ELSE 0
        END
    ), 0)
    FROM dbo.suppliers s
    OUTER APPLY
    (
        SELECT SUM(
            CASE
                WHEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                    THEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                ELSE 0
            END
        ) AS ImportDebt
        FROM dbo.imports i
        OUTER APPLY
        (
            SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE i.supplier_id = s.supplier_id
          AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ) d
    OUTER APPLY
    (
        SELECT SUM(ISNULL(amount, 0)) AS TotalPaid
        FROM dbo.supplier_payments
        WHERE supplier_id = s.supplier_id
    ) paid;

    SELECT
        ISNULL(@NetRevenue, 0) AS TotalRevenue,
        ISNULL(@NetPurchase, 0) AS TotalCost,
        ISNULL(@OrderCount, 0) AS OrderCount,
        ISNULL(@GrossProfit, 0) AS GrossProfit,
        ISNULL(@CashbookIncome, 0) AS CashbookIncome,
        ISNULL(@CashbookExpense, 0) AS CashbookExpense,
        ISNULL(@NetProfitAfterCashbook, 0) AS NetProfitAfterCashbook,
        ISNULL(@TotalDebtCustomer, 0) AS TotalDebtCustomer,
        ISNULL(@TotalDebtSupplier, 0) AS TotalDebtSupplier,
        ISNULL(@GrossSales, 0) AS GrossSales,
        ISNULL(@CustomerReturnAmount, 0) AS CustomerReturnAmount,
        ISNULL(@TotalPurchase, 0) AS TotalPurchase,
        ISNULL(@PurchaseReturnAmount, 0) AS PurchaseReturnAmount,
        ISNULL(@CostOfGoodsSold, 0) AS CostOfGoodsSold;
END
GO
