/*
  MigrationId: 20260908_full_business_audit
  Based on SQL_DB.sql exported 08/09/2026 15:45; SHA256:
  321A5E1C4FDD31C028432276A0516779C669F79F0BBEDFB0FB381D025446B765
  Run on the shop database after backup, before using the updated application.
  Does not create/select a database, change file paths or rewrite business data.
  Preserves prior sales-audit fixes. Standalone/updater transaction; rerunnable.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb')
   OR OBJECT_ID(N'dbo.Report_GetOverview',N'P') IS NULL
   OR OBJECT_ID(N'dbo.batch_inventory_movements',N'U') IS NULL
   OR OBJECT_ID(N'dbo.order_item_batch_selections',N'U') IS NULL
   OR COL_LENGTH(N'dbo.supplier_debt_adjustments',N'adjustment_type') IS NULL
   OR COL_LENGTH(N'dbo.imports',N'supplier_refund_received') IS NULL
   OR COL_LENGTH(N'dbo.purchase_returns',N'settlement_type') IS NULL
    THROW 51421,N'Chọn đúng database có schema SQL mới nhất trước khi chạy migration.',1;

DECLARE @OwnTransaction BIT=CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
BEGIN TRY
    IF @OwnTransaction=1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FullBusinessAudit;

    EXEC sys.sp_executesql N'CREATE OR ALTER VIEW dbo.vw_SupplierAccountBalances
AS
SELECT s.supplier_id AS SupplierId,
       CAST(ISNULL(i.Amount,0)-ISNULL(r.Amount,0)-ISNULL(p.Amount,0)-ISNULL(a.Amount,0) AS DECIMAL(18,0)) AS AccountBalance
FROM dbo.suppliers s
OUTER APPLY (
    SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0)+ISNULL(supplier_refund_received,0)) Amount
    FROM dbo.imports WHERE supplier_id=s.supplier_id AND ISNULL(status,N'''') IN (N''Completed'',N''Paid'')
) i
OUTER APPLY (
    SELECT SUM(ISNULL(total_amount,0)) Amount FROM dbo.purchase_returns
    WHERE supplier_id=s.supplier_id AND ISNULL(status,N'''')<>N''Cancelled''
      AND ISNULL(settlement_type,N''DEBT_OFFSET'')=N''DEBT_OFFSET''
) r
OUTER APPLY (SELECT SUM(ISNULL(amount,0)) Amount FROM dbo.supplier_payments WHERE supplier_id=s.supplier_id) p
OUTER APPLY (
    SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE'' THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END) Amount
    FROM dbo.supplier_debt_adjustments WHERE supplier_id=s.supplier_id
) a;';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Report_GetSupplierStatistics
    @FromDate DATETIME, @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 50 s.supplier_id SupplierId, ISNULL(s.supplier_name,N''Không xác định'') SupplierName,
           ISNULL(s.phone,N'''') Phone, ISNULL(i.Amount,0) TotalImportAmount,
           ISNULL(r.Amount,0) TotalReturnAmount,
           CASE WHEN b.AccountBalance>0 THEN b.AccountBalance ELSE 0 END CurrentDebt
    FROM dbo.suppliers s
    JOIN dbo.vw_SupplierAccountBalances b ON b.SupplierId=s.supplier_id
    OUTER APPLY (
        SELECT SUM(ISNULL(final_amount,0)) Amount FROM dbo.imports
        WHERE supplier_id=s.supplier_id AND import_date BETWEEN @FromDate AND @ToDate
          AND status IN (N''Completed'',N''Paid'')
    ) i
    OUTER APPLY (
        SELECT SUM(ISNULL(total_amount,0)) Amount FROM dbo.purchase_returns
        WHERE supplier_id=s.supplier_id AND return_date BETWEEN @FromDate AND @ToDate
          AND ISNULL(status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'')
    ) r
    WHERE ISNULL(i.Amount,0)>0 OR ISNULL(r.Amount,0)>0 OR b.AccountBalance>0
    ORDER BY ISNULL(i.Amount,0) DESC, s.supplier_id;
END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE [dbo].[Report_GetInventoryMovement]
    @FromDate DATETIME,
    @ToDate   DATETIME,
    @Keyword  NVARCHAR(200) = N''''
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME;
    DECLARE @EndDateExclusive DATETIME;

    SET @StartDate = CONVERT(DATE, @FromDate);
    SET @EndDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));
    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'''')));

    ;WITH Movements AS
    (
        -- Nhập mua từ nhà cung cấp: tăng kho
        SELECT
            id.product_id,
            i.import_date AS movement_date,
            CAST(ISNULL(id.base_quantity, id.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(id.total, ISNULL(id.import_price, 0) * ISNULL(id.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N''PURCHASE_IN'' AS movement_type
        FROM dbo.import_details id
        INNER JOIN dbo.imports i ON i.import_id = id.import_id
        WHERE ISNULL(i.status, N'''') IN (N''Completed'', N''Paid'')
          AND i.import_date IS NOT NULL
          AND id.product_id IS NOT NULL

        UNION ALL

        -- Trả hàng nhà cung cấp: giảm kho
        SELECT
            prd.product_id,
            pr.return_date AS movement_date,
            -CAST(COALESCE(NULLIF(prd.base_quantity,0), prd.quantity * ISNULL(NULLIF(prd.unit_conversion_to_base,0),1)) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(prd.total, ISNULL(prd.import_price, 0) * ISNULL(prd.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N''SUPPLIER_RETURN_OUT'' AS movement_type
        FROM dbo.purchase_return_details prd
        INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
        WHERE ISNULL(pr.status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'')
          AND pr.return_date IS NOT NULL
          AND prd.product_id IS NOT NULL

        UNION ALL

        -- Xuất bán: giảm kho
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            -CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N''SALES_OUT'' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'''') IN (N''Paid'', N''Completed'')
          AND ISNULL(o.order_type, N'''') <> N''RETURN''
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND ISNULL(oi.quantity, 0) > 0

        UNION ALL

        -- Khách trả hàng: tăng kho
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3))) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N''RETURN_IN'' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'''') IN (N''Paid'', N''Completed'')
          AND ISNULL(o.order_type, N'''') = N''RETURN''
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL

        UNION ALL

        -- Kiểm kê/chốt kho: tăng hoặc giảm theo cột difference
        SELECT
            icd.product_id,
            ic.check_date AS movement_date,
            CAST(icd.difference AS DECIMAL(18, 3)) AS qty,
            CAST(0 AS DECIMAL(18, 0)) AS amount,
            N''STOCKTAKE'' AS movement_type
        FROM dbo.inventory_check_details icd
        INNER JOIN dbo.inventory_checks ic ON ic.check_id = icd.check_id
        WHERE ic.check_date IS NOT NULL
          AND icd.product_id IS NOT NULL
          AND ISNULL(icd.difference, 0) <> 0

        UNION ALL

        -- Expired-batch disposal is a real stock-out, not opening stock.
        SELECT b.product_id, m.created_at,
               CAST(m.quantity_change AS DECIMAL(18,3)),
               CAST(0 AS DECIMAL(18,0)), N''EXPIRED_WRITE_OFF''
        FROM dbo.batch_inventory_movements m
        JOIN dbo.product_batches b ON b.batch_id=m.batch_id
        WHERE m.movement_type=N''EXPIRED_WRITE_OFF'' AND m.quantity_change<0
    ),
    PeriodSummary AS
    (
        SELECT
            product_id,
            SUM(CASE WHEN movement_type = N''PURCHASE_IN''          AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS PurchaseInQty,
            SUM(CASE WHEN movement_type = N''SUPPLIER_RETURN_OUT''  AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SupplierReturnOutQty,
            SUM(CASE WHEN movement_type = N''SALES_OUT''            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SalesOutQty,
            SUM(CASE WHEN movement_type = N''RETURN_IN''            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS ReturnInQty,
            SUM(CASE WHEN movement_type = N''EXPIRED_WRITE_OFF'' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS ExpiredWriteOffQty,
            SUM(CASE WHEN movement_type = N''STOCKTAKE''            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS StocktakeAdjustQty,
            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N''PURCHASE_IN''          AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N''SUPPLIER_RETURN_OUT''  AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SupplierReturnOutValue,
            SUM(CASE WHEN movement_type = N''SALES_OUT''            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue
        FROM Movements
        GROUP BY product_id
    ),
    AfterPeriodSummary AS
    (
        SELECT
            product_id,
            SUM(qty) AS NetAfterPeriodQty
        FROM Movements
        WHERE movement_date >= @EndDateExclusive
        GROUP BY product_id
    )
    SELECT
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        ISNULL(p.barcode, N'''') AS Barcode,
        p.product_name AS ProductName,
        ISNULL(c.category_name, N'''') AS CategoryName,
        ISNULL(u.unit_name, N'''') AS UnitName,

        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) - ISNULL(ps.NetPeriodQty, 0) AS DECIMAL(18, 3)) AS OpeningStock,
        CAST(ISNULL(ps.PurchaseInQty, 0) AS DECIMAL(18, 3)) AS PurchaseInQty,
        CAST(ISNULL(ps.ReturnInQty, 0) AS DECIMAL(18, 3)) AS ReturnInQty,
        CAST(ISNULL(ps.SupplierReturnOutQty, 0) AS DECIMAL(18, 3)) AS SupplierReturnOutQty,
        CAST(ISNULL(ps.ExpiredWriteOffQty,0) AS DECIMAL(18,3)) AS ExpiredWriteOffQty,
        CAST(ISNULL(ps.StocktakeAdjustQty, 0) AS DECIMAL(18, 3)) AS StocktakeAdjustQty,
        CAST(ISNULL(ps.SalesOutQty, 0) AS DECIMAL(18, 3)) AS SalesOutQty,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) AS DECIMAL(18, 3)) AS ClosingStock,
        CAST(ISNULL(p.stock, 0) AS DECIMAL(18, 3)) AS CurrentStock,

        CAST(ISNULL(ps.PurchaseInValue, 0) AS DECIMAL(18, 0)) AS PurchaseInValue,
        CAST(ISNULL(ps.SupplierReturnOutValue, 0) AS DECIMAL(18, 0)) AS SupplierReturnOutValue,
        CAST(ISNULL(ps.SalesOutValue, 0) AS DECIMAL(18, 0)) AS SalesOutValue,
        CAST((ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0)) * ISNULL(p.import_price, 0) AS DECIMAL(18, 0)) AS ClosingCostValue
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON c.category_id = p.category_id
    LEFT JOIN dbo.Units u ON u.unit_id = p.unit_id
    LEFT JOIN PeriodSummary ps ON ps.product_id = p.product_id
    LEFT JOIN AfterPeriodSummary a ON a.product_id = p.product_id
    WHERE ISNULL(p.is_active, 1) = 1
      AND (
            @Keyword = N''''
            OR p.product_code LIKE N''%'' + @Keyword + N''%''
            OR ISNULL(p.barcode, N'''') LIKE N''%'' + @Keyword + N''%''
            OR p.product_name LIKE N''%'' + @Keyword + N''%''
          )
    ORDER BY p.product_code, p.product_name;
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
      AND ISNULL(status, N'''') IN (N''Completed'', N''Paid'');

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
                -1 * ISNULL(oi.cost_price, ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
            ELSE
                ISNULL(oi.cost_price, ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
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

    -- Current sales debt, not the original unpaid invoice total. Keep signed
    -- return credits and adjustments; never offset one customer against another.
    -- Repair-inclusive overview is supplied by CustomerDebtLedger in the app.
    SELECT @TotalDebtCustomer = ISNULL(SUM(CASE WHEN d.CurrentDebt > 0 THEN d.CurrentDebt ELSE 0 END), 0)
    FROM dbo.customers c
    CROSS APPLY
    (
        SELECT
            ISNULL((SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                    FROM dbo.orders WHERE customer_id=c.customer_id
                    AND ISNULL(status,N'''') NOT IN (N''Cancelled'',N''Pending'')),0)
            - ISNULL((SELECT SUM(ISNULL(amount,0)) FROM dbo.customer_payments
                      WHERE customer_id=c.customer_id),0)
            - ISNULL((SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE''
                                     THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END)
                      FROM dbo.customer_debt_adjustments WHERE customer_id=c.customer_id),0) AS CurrentDebt
    ) d;

    SELECT @TotalDebtSupplier=ISNULL(SUM(CASE WHEN AccountBalance>0 THEN AccountBalance ELSE 0 END),0)
    FROM dbo.vw_SupplierAccountBalances;

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

    IF @OwnTransaction=1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
    ELSE IF @OwnTransaction=0 AND XACT_STATE()=1 ROLLBACK TRANSACTION FullBusinessAudit;
    THROW;
END CATCH;
