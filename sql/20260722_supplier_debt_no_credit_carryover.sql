/* Hotfix 2026-07-22
   - Do not let negative debt from old purchase invoices reduce new supplier debt.
   - Supplier debt is now: sum(max(import final - paid at import - returned to supplier, 0)) - supplier debt payments.

   Safe to run on an existing customer database. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.SupplierPayments_GetDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.SupplierPayments_GetDebt @supplier_id INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[SupplierPayments_GetDebt]
    @supplier_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ImportDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(
            CASE
                WHEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                    THEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                ELSE 0
            END
        )
        FROM dbo.imports i
        OUTER APPLY
        (
            SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE i.supplier_id = @supplier_id
          AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    DECLARE @TotalPaidAfter DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.supplier_payments
        WHERE supplier_id = @supplier_id
    ), 0);

    DECLARE @CurrentDebt DECIMAL(18,0) = @ImportDebt - @TotalPaidAfter;
    IF @CurrentDebt < 0 SET @CurrentDebt = 0;

    SELECT @CurrentDebt AS CurrentDebt;
END
GO

IF OBJECT_ID(N'dbo.sp_GetSupplierDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_GetSupplierDebt @supplier_id INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[sp_GetSupplierDebt]
    @supplier_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ImportDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(
            CASE
                WHEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                    THEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                ELSE 0
            END
        )
        FROM dbo.imports i
        OUTER APPLY
        (
            SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE i.supplier_id = @supplier_id
          AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    DECLARE @TotalPaidAfter DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.supplier_payments
        WHERE supplier_id = @supplier_id
    ), 0);

    DECLARE @CurrentDebt DECIMAL(18,0) = @ImportDebt - @TotalPaidAfter;
    IF @CurrentDebt < 0 SET @CurrentDebt = 0;

    SELECT @CurrentDebt AS CurrentDebt;
END
GO

IF OBJECT_ID(N'dbo.Suppliers_GetWithDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_GetWithDebt AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Suppliers_GetWithDebt]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM
    (
        SELECT
            s.supplier_id AS SupplierId,
            ISNULL(s.supplier_name, N'') AS SupplierName,
            ISNULL(s.phone, N'') AS Phone,
            ISNULL(s.address, N'') AS Address,
            ISNULL(s.email, N'') AS Email,
            ISNULL(s.tax_code, N'') AS TaxCode,
            ISNULL(s.is_active, 1) AS IsActive,
            CASE
                WHEN ISNULL(d.ImportDebt, 0) - ISNULL(p.TotalPaid, 0) > 0
                    THEN ISNULL(d.ImportDebt, 0) - ISNULL(p.TotalPaid, 0)
                ELSE 0
            END AS CurrentDebt
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
        ) p
    ) X
    WHERE X.CurrentDebt > 0
    ORDER BY X.SupplierName;
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
        ISNULL(@TotalDebtCustomer, 0) AS TotalDebtCustomer,
        ISNULL(@TotalDebtSupplier, 0) AS TotalDebtSupplier,
        ISNULL(@GrossSales, 0) AS GrossSales,
        ISNULL(@CustomerReturnAmount, 0) AS CustomerReturnAmount,
        ISNULL(@TotalPurchase, 0) AS TotalPurchase,
        ISNULL(@PurchaseReturnAmount, 0) AS PurchaseReturnAmount,
        ISNULL(@CostOfGoodsSold, 0) AS CostOfGoodsSold;
END
GO

IF OBJECT_ID(N'dbo.Report_GetSupplierStatistics', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Report_GetSupplierStatistics @FromDate DATETIME, @ToDate DATETIME AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Report_GetSupplierStatistics]
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH SupplierRows AS
    (
        SELECT
            s.supplier_id AS SupplierId,
            ISNULL(s.supplier_name, N'Không xác định') AS SupplierName,
            ISNULL(s.phone, N'') AS Phone,
            ISNULL(SUM(i.final_amount), 0) AS TotalImportAmount,
            ISNULL(ret.TotalReturnAmount, 0) AS TotalReturnAmount,
            CASE
                WHEN ISNULL(d.ImportDebt, 0) - ISNULL(paid.TotalPaid, 0) > 0
                    THEN ISNULL(d.ImportDebt, 0) - ISNULL(paid.TotalPaid, 0)
                ELSE 0
            END AS CurrentDebt
        FROM dbo.suppliers s
        LEFT JOIN dbo.imports i ON s.supplier_id = i.supplier_id
            AND i.import_date BETWEEN @FromDate AND @ToDate
            AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        OUTER APPLY
        (
            SELECT SUM(ISNULL(pr.total_amount, 0)) AS TotalReturnAmount
            FROM dbo.purchase_returns pr
            WHERE pr.supplier_id = s.supplier_id
              AND pr.return_date BETWEEN @FromDate AND @ToDate
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) ret
        OUTER APPLY
        (
            SELECT SUM(
                CASE
                    WHEN ISNULL(all_i.final_amount, 0) - ISNULL(all_i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                        THEN ISNULL(all_i.final_amount, 0) - ISNULL(all_i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                    ELSE 0
                END
            ) AS ImportDebt
            FROM dbo.imports all_i
            OUTER APPLY
            (
                SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
                FROM dbo.purchase_returns pr
                WHERE pr.import_id = all_i.import_id
                  AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
            ) r
            WHERE all_i.supplier_id = s.supplier_id
              AND ISNULL(all_i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) d
        OUTER APPLY
        (
            SELECT SUM(ISNULL(amount, 0)) AS TotalPaid
            FROM dbo.supplier_payments
            WHERE supplier_id = s.supplier_id
        ) paid
        GROUP BY s.supplier_id, s.supplier_name, s.phone, ret.TotalReturnAmount, d.ImportDebt, paid.TotalPaid
    )
    SELECT TOP 50
        SupplierId,
        SupplierName,
        Phone,
        TotalImportAmount,
        TotalReturnAmount,
        CurrentDebt
    FROM SupplierRows
    WHERE TotalImportAmount > 0 OR CurrentDebt > 0
    ORDER BY TotalImportAmount DESC;
END
GO
