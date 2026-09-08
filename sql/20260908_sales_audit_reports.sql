/*
  MigrationId: 20260908_sales_audit_reports
  Run against the shop database, after backing it up.
  Requires the schema exported in SQL_DB.sql (08/09/2026).
  Idempotent; changes only two report procedures. No transaction rows are edited.
  Keep SQL_DB.sql as the original snapshot; apply this file after it for new installs.
  Safe both standalone and inside OnlineSqlUpdater's existing transaction.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
   OR OBJECT_ID(N'dbo.orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Report_GetOverview', N'P') IS NULL
   OR OBJECT_ID(N'dbo.Report_GetDetailedLedger', N'P') IS NULL
    THROW 51410, N'Chọn đúng database cửa hàng có schema SQL_DB.sql trước khi chạy migration.', 1;

DECLARE @OwnTransaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
BEGIN TRY
    IF @OwnTransaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION SalesAuditReports;

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE [dbo].[Report_GetDetailedLedger]
    @FromDate DATE,
    @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        o.order_code AS InvoiceId,
        o.order_date AS InvoiceDate,
        ISNULL(c.name, N''Khách lẻ'') AS CustomerName,
        -- Return documents are negative revenue, not additional sales.
        CASE WHEN ISNULL(o.order_type, N'''') = N''RETURN''
             THEN -ABS(o.final_amount) ELSE o.final_amount END AS TotalAmount
    FROM dbo.orders o
    LEFT JOIN dbo.customers c ON c.customer_id = o.customer_id
    WHERE CAST(o.order_date AS DATE) >= @FromDate
      AND CAST(o.order_date AS DATE) <= @ToDate
      AND ISNULL(o.status, N'''') IN (N''Completed'', N''Paid'', N''Partial'')
    ORDER BY o.order_date, o.order_id;
END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE [dbo].[Report_GetOverview]
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME = @FromDate;
    DECLARE @EndDate DATETIME = @ToDate;
    DECLARE @CashbookStartDate DATETIME = DATEADD(DAY, DATEDIFF(DAY, 0, @FromDate), 0);
    DECLARE @CashbookEndExclusive DATETIME = DATEADD(DAY, DATEDIFF(DAY, 0, @ToDate) + 1, 0);

    DECLARE @GrossSales DECIMAL(18,0) = 0;
    DECLARE @CustomerReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetRevenue DECIMAL(18,0) = 0;

    DECLARE @TotalPurchase DECIMAL(18,0) = 0;
    DECLARE @PurchaseReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetPurchase DECIMAL(18,0) = 0;

    DECLARE @OrderCount INT = 0;
    DECLARE @CostOfGoodsSold DECIMAL(18,0) = 0;
    DECLARE @GrossProfit DECIMAL(18,0) = 0;

    DECLARE @CashbookTotalIncome DECIMAL(18,0) = 0;
    DECLARE @CashbookTotalExpense DECIMAL(18,0) = 0;
    DECLARE @CashbookIncome DECIMAL(18,0) = 0;
    DECLARE @CashbookExpense DECIMAL(18,0) = 0;
    DECLARE @NetProfitAfterCashbook DECIMAL(18,0) = 0;

    DECLARE @TotalDebtCustomer DECIMAL(18,0) = 0;
    DECLARE @TotalDebtSupplier DECIMAL(18,0) = 0;

    SELECT @GrossSales = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'''') IN (N''Completed'', N''Paid'', N''Partial'')
      AND ISNULL(order_type, N'''') <> N''RETURN'';

    SELECT @CustomerReturnAmount = ISNULL(SUM(ABS(ISNULL(final_amount, 0))), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'''') IN (N''Completed'', N''Paid'', N''Partial'')
      AND ISNULL(order_type, N'''') = N''RETURN'';

    SET @NetRevenue = ISNULL(@GrossSales, 0) - ISNULL(@CustomerReturnAmount, 0);
    -- Returns from earlier periods may make net revenue negative.

    SELECT @TotalPurchase = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.imports
    WHERE import_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'');

    SELECT @PurchaseReturnAmount = ISNULL(SUM(ISNULL(total_amount, 0)), 0)
    FROM dbo.purchase_returns
    WHERE return_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'');

    SET @NetPurchase = ISNULL(@TotalPurchase, 0) - ISNULL(@PurchaseReturnAmount, 0);
    IF @NetPurchase < 0 SET @NetPurchase = 0;

    SELECT @OrderCount = COUNT(*)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'''') IN (N''Completed'', N''Paid'', N''Partial'')
      AND ISNULL(order_type, N'''') <> N''RETURN'';

    SELECT @CostOfGoodsSold = ISNULL(SUM(
        CASE
            WHEN ISNULL(o.order_type, N'''') = N''RETURN'' THEN
                -1 * ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
            ELSE
                ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
        END
    ), 0)
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON o.order_id = oi.order_id
    LEFT JOIN dbo.products p ON p.product_id = oi.product_id
    WHERE o.order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(o.status, N'''') IN (N''Completed'', N''Paid'', N''Partial'')
      AND oi.product_id IS NOT NULL;

    -- Preserve signed returned cost so return-period profit stays correct.

    SET @GrossProfit = ISNULL(@NetRevenue, 0) - ISNULL(@CostOfGoodsSold, 0);

    IF OBJECT_ID(N''dbo.cashbook_entries'', N''U'') IS NOT NULL
       AND OBJECT_ID(N''dbo.cashbook_categories'', N''U'') IS NOT NULL
    BEGIN
        DECLARE @CashbookSql NVARCHAR(MAX);

        SET @CashbookSql = N''
SELECT
    @TotalIncomeOut = ISNULL(SUM(CASE WHEN e.entry_type = N''''IN'''' THEN e.amount ELSE 0 END), 0),
    @TotalExpenseOut = ISNULL(SUM(CASE WHEN e.entry_type = N''''OUT'''' THEN e.amount ELSE 0 END), 0),
    @IncomeOut = ISNULL(SUM(CASE WHEN e.entry_type = N''''IN'''' AND ISNULL(c.affects_profit, 1) = 1 THEN e.amount ELSE 0 END), 0),
    @ExpenseOut = ISNULL(SUM(CASE WHEN e.entry_type = N''''OUT'''' AND ISNULL(c.affects_profit, 1) = 1 THEN e.amount ELSE 0 END), 0)
FROM dbo.cashbook_entries e
LEFT JOIN dbo.cashbook_categories c ON c.category_id = e.category_id
WHERE e.is_deleted = 0
  AND e.entry_date >= @StartDateIn
  AND e.entry_date < @EndDateExclusiveIn;'';

        EXEC sp_executesql
            @CashbookSql,
            N''@StartDateIn DATETIME, @EndDateExclusiveIn DATETIME, @TotalIncomeOut DECIMAL(18,0) OUTPUT, @TotalExpenseOut DECIMAL(18,0) OUTPUT, @IncomeOut DECIMAL(18,0) OUTPUT, @ExpenseOut DECIMAL(18,0) OUTPUT'',
            @StartDateIn = @CashbookStartDate,
            @EndDateExclusiveIn = @CashbookEndExclusive,
            @TotalIncomeOut = @CashbookTotalIncome OUTPUT,
            @TotalExpenseOut = @CashbookTotalExpense OUTPUT,
            @IncomeOut = @CashbookIncome OUTPUT,
            @ExpenseOut = @CashbookExpense OUTPUT;
    END

    SET @NetProfitAfterCashbook =
        ISNULL(@GrossProfit, 0) + ISNULL(@CashbookIncome, 0) - ISNULL(@CashbookExpense, 0);

    SELECT @TotalDebtCustomer = ISNULL(SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0)), 0)
    FROM dbo.orders
    WHERE ISNULL(status, N'''') IN (N''Completed'', N''Partial'')
      AND ISNULL(final_amount, 0) > ISNULL(paid_amount, 0)
      AND ISNULL(order_type, N'''') <> N''RETURN'';

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
              AND ISNULL(pr.status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'')
        ) r
        WHERE i.supplier_id = s.supplier_id
          AND ISNULL(i.status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'')
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
        ISNULL(@CashbookTotalIncome, 0) AS CashbookTotalIncome,
        ISNULL(@CashbookTotalExpense, 0) AS CashbookTotalExpense,
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
END';

    IF @OwnTransaction = 1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @OwnTransaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION SalesAuditReports;
    THROW;
END CATCH;

