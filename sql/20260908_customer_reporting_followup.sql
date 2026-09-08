/*
  MigrationId: 20260908_customer_reporting_followup
  Based on current SQL_DB.sql exported 08/09/2026; SHA256:
  3EB38C744D3D78E09D18E45F2E867646A4AD6142224C89B851099500154D1FC1

  Run after 20260908_full_business_audit.sql on the shop database.
  Fixes customer history/top-customer reporting and legacy staff/cashier reports.
  Does not create/select a database or rewrite business transactions.
  Rerunnable inside an updater-owned transaction.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
   OR OBJECT_ID(N'dbo.orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.order_items', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customer_payments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customer_debt_adjustments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.repair_orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Customer_GetTop', N'P') IS NULL
   OR OBJECT_ID(N'dbo.Report_GetRevenueByCashier', N'P') IS NULL
   OR OBJECT_ID(N'dbo.Report_GetRevenueBySalesperson', N'P') IS NULL
    THROW 51431, N'Chọn đúng database HoaTran POS đã chạy migration nghiệp vụ trước khi chạy migration báo cáo khách hàng.', 1;

DECLARE @OwnTransaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
BEGIN TRY
    IF @OwnTransaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION CustomerReportingFollowup;

    -- Keep old direct callers on the same signed sales-and-repair debt formula as the ledger.
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Customer_GetCurrentDebt
        @CustomerId INT
    AS
    BEGIN
        SET NOCOUNT ON;

        DECLARE @CurrentDebt DECIMAL(18,0) =
            ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.orders
                WHERE customer_id=@CustomerId
                  AND ISNULL(status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'',N''Pending'')
            ),0)
            + ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.repair_orders
                WHERE customer_id=@CustomerId
                  AND ISNULL(status,N'''') NOT IN (N''CANCELLED'',N''DECLINED'',N''UNREPAIRABLE'')
                  AND (ISNULL(quote_status,N'''')=N''APPROVED'' OR ISNULL(paid_amount,0)>0)
            ),0)
            - ISNULL((
                SELECT SUM(ISNULL(amount,0))
                FROM dbo.customer_payments
                WHERE customer_id=@CustomerId
            ),0)
            - ISNULL((
                SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE''
                                THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END)
                FROM dbo.customer_debt_adjustments
                WHERE customer_id=@CustomerId
            ),0);

        SELECT CASE WHEN @CurrentDebt>0 THEN @CurrentDebt ELSE 0 END AS CurrentDebt;
    END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.CustomerPayments_GetDebt
        @CustomerId INT
    AS
    BEGIN
        SET NOCOUNT ON;

        DECLARE @CurrentDebt DECIMAL(18,0) =
            ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.orders
                WHERE customer_id=@CustomerId
                  AND ISNULL(status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'',N''Pending'')
            ),0)
            + ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.repair_orders
                WHERE customer_id=@CustomerId
                  AND ISNULL(status,N'''') NOT IN (N''CANCELLED'',N''DECLINED'',N''UNREPAIRABLE'')
                  AND (ISNULL(quote_status,N'''')=N''APPROVED'' OR ISNULL(paid_amount,0)>0)
            ),0)
            - ISNULL((
                SELECT SUM(ISNULL(amount,0))
                FROM dbo.customer_payments
                WHERE customer_id=@CustomerId
            ),0)
            - ISNULL((
                SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE''
                                THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END)
                FROM dbo.customer_debt_adjustments
                WHERE customer_id=@CustomerId
            ),0);

        SELECT CASE WHEN @CurrentDebt>0 THEN @CurrentDebt ELSE 0 END AS CurrentDebt;
    END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Customer_GetTop
        @TopCount INT = 20,
        @FromDate DATETIME = NULL,
        @ToDate DATETIME = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        IF @TopCount IS NULL OR @TopCount<=0 SET @TopCount=20;

        ;WITH CustomerOrders AS
        (
            SELECT
                c.customer_id AS CustomerId,
                c.name AS CustomerName,
                c.phone AS Phone,
                c.email AS Email,
                c.address AS Address,
                c.points AS Points,
                c.created_at AS CreatedAt,
                o.order_id AS OrderId,
                o.order_date AS OrderDate,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN''
                     THEN -ABS(ISNULL(o.final_amount,ISNULL(o.total_amount,0)))
                     ELSE ABS(ISNULL(o.final_amount,ISNULL(o.total_amount,0))) END AS NetRevenue,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN''
                     THEN -ISNULL(costs.CostOfGoodsSold,0)
                     ELSE ISNULL(costs.CostOfGoodsSold,0) END AS NetCost,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN'' THEN 0 ELSE 1 END AS SalesOrderCount
            FROM dbo.customers c
            INNER JOIN dbo.orders o ON c.customer_id=o.customer_id
            OUTER APPLY
            (
                SELECT SUM(ISNULL(oi.cost_price,ISNULL(p.import_price,0))
                           * ABS(CAST(ISNULL(oi.base_quantity,oi.quantity) AS DECIMAL(18,3)))) AS CostOfGoodsSold
                FROM dbo.order_items oi
                LEFT JOIN dbo.products p ON p.product_id=oi.product_id
                WHERE oi.order_id=o.order_id
            ) costs
            WHERE (@FromDate IS NULL OR o.order_date>=@FromDate)
              AND (@ToDate IS NULL OR o.order_date<DATEADD(DAY,1,@ToDate))
              AND ISNULL(o.status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'',N''Pending'')
        )
        SELECT TOP (@TopCount)
            co.CustomerId,co.CustomerName,co.Phone,co.Email,co.Address,co.Points,co.CreatedAt,
            SUM(co.SalesOrderCount) AS TotalOrders,
            ISNULL(SUM(co.NetRevenue),0) AS TotalRevenue,
            ISNULL(SUM(co.NetCost),0) AS TotalCost,
            ISNULL(SUM(co.NetRevenue-co.NetCost),0) AS GrossProfit,
            CASE WHEN ISNULL(SUM(co.NetRevenue),0)=0 THEN 0
                 ELSE ISNULL(SUM(co.NetRevenue-co.NetCost),0)*100.0/NULLIF(SUM(co.NetRevenue),0) END AS ProfitMargin,
            MIN(co.OrderDate) AS FirstOrderDate,
            MAX(co.OrderDate) AS LastOrderDate,
            ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.orders o
                WHERE o.customer_id=co.CustomerId
                  AND ISNULL(o.status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'',N''Pending'')
            ),0)
            + ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.repair_orders ro
                WHERE ro.customer_id=co.CustomerId
                  AND ISNULL(ro.status,N'''') NOT IN (N''CANCELLED'',N''DECLINED'',N''UNREPAIRABLE'')
                  AND (ISNULL(ro.quote_status,N'''')=N''APPROVED'' OR ISNULL(ro.paid_amount,0)>0)
            ),0)
            - ISNULL((SELECT SUM(ISNULL(amount,0)) FROM dbo.customer_payments p WHERE p.customer_id=co.CustomerId),0)
            - ISNULL((
                SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE''
                                THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END)
                FROM dbo.customer_debt_adjustments a WHERE a.customer_id=co.CustomerId
            ),0) AS CurrentDebt
        FROM CustomerOrders co
        GROUP BY co.CustomerId,co.CustomerName,co.Phone,co.Email,co.Address,co.Points,co.CreatedAt
        ORDER BY TotalRevenue DESC;
    END';

    -- This procedure is retained for existing external callers; the current UI uses
    -- ReportData.GetCustomerProfitReport but must get the same snapshot-cost rule.
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Report_GetCustomerProfitByCustomer
        @FromDate DATETIME,
        @ToDate DATETIME,
        @TopCount INT = 20
    AS
    BEGIN
        SET NOCOUNT ON;
        IF @TopCount IS NULL OR @TopCount<=0 SET @TopCount=20;

        ;WITH CustomerOrders AS
        (
            SELECT
                c.customer_id AS CustomerId,
                ISNULL(NULLIF(LTRIM(RTRIM(c.customer_code)),N''''),N''KH''+RIGHT(N''000000''+CAST(c.customer_id AS NVARCHAR(20)),6)) AS CustomerCode,
                ISNULL(c.name,N'''') AS CustomerName,
                ISNULL(c.phone,N'''') AS Phone,
                ISNULL(c.address,N'''') AS Address,
                ISNULL(c.points,0) AS Points,
                o.order_id AS OrderId,
                o.order_date AS OrderDate,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN''
                     THEN -ABS(ISNULL(o.final_amount,ISNULL(o.total_amount,0)))
                     ELSE ABS(ISNULL(o.final_amount,ISNULL(o.total_amount,0))) END AS NetRevenue,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN''
                     THEN -ISNULL(costs.CostOfGoodsSold,0)
                     ELSE ISNULL(costs.CostOfGoodsSold,0) END AS NetCost,
                CASE WHEN ISNULL(o.order_type,N'''')=N''RETURN'' THEN 0 ELSE 1 END AS SalesOrderCount
            FROM dbo.customers c
            INNER JOIN dbo.orders o ON c.customer_id=o.customer_id
            OUTER APPLY
            (
                SELECT SUM(ISNULL(oi.cost_price,ISNULL(p.import_price,0))
                           * ABS(CAST(ISNULL(oi.base_quantity,oi.quantity) AS DECIMAL(18,3)))) AS CostOfGoodsSold
                FROM dbo.order_items oi
                LEFT JOIN dbo.products p ON p.product_id=oi.product_id
                WHERE oi.order_id=o.order_id
            ) costs
            WHERE o.order_date BETWEEN @FromDate AND @ToDate
              AND ISNULL(o.status,N'''') IN (N''Completed'',N''Paid'',N''Partial'')
        ), Aggregated AS
        (
            SELECT TOP (@TopCount)
                co.CustomerId,co.CustomerCode,co.CustomerName,co.Phone,co.Address,co.Points,
                SUM(co.SalesOrderCount) AS TotalOrders,
                ISNULL(SUM(co.NetRevenue),0) AS TotalRevenue,
                ISNULL(SUM(co.NetCost),0) AS TotalCost,
                ISNULL(SUM(co.NetRevenue-co.NetCost),0) AS GrossProfit,
                CASE WHEN ISNULL(SUM(co.NetRevenue),0)=0 THEN 0
                     ELSE ISNULL(SUM(co.NetRevenue-co.NetCost),0)*100.0/NULLIF(SUM(co.NetRevenue),0) END AS ProfitMargin,
                MIN(co.OrderDate) AS FirstOrderDate,MAX(co.OrderDate) AS LastOrderDate
            FROM CustomerOrders co
            GROUP BY co.CustomerId,co.CustomerCode,co.CustomerName,co.Phone,co.Address,co.Points
            ORDER BY TotalRevenue DESC
        )
        SELECT a.CustomerId,a.CustomerCode,a.CustomerName,a.Phone,a.Address,
               CASE WHEN ISNULL(debt.CurrentDebt,0)>0 THEN debt.CurrentDebt ELSE 0 END AS CurrentDebt,
               a.Points,a.TotalOrders,a.TotalRevenue,a.TotalCost,a.GrossProfit,a.ProfitMargin,a.FirstOrderDate,a.LastOrderDate
        FROM Aggregated a
        OUTER APPLY
        (
            SELECT ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.orders o
                WHERE o.customer_id=a.CustomerId
                  AND ISNULL(o.status,N'''') NOT IN (N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'',N''Pending'')
            ),0)
            + ISNULL((
                SELECT SUM(ISNULL(final_amount,0)-ISNULL(paid_amount,0))
                FROM dbo.repair_orders ro
                WHERE ro.customer_id=a.CustomerId
                  AND ISNULL(ro.status,N'''') NOT IN (N''CANCELLED'',N''DECLINED'',N''UNREPAIRABLE'')
                  AND (ISNULL(ro.quote_status,N'''')=N''APPROVED'' OR ISNULL(ro.paid_amount,0)>0)
            ),0)
            - ISNULL((SELECT SUM(ISNULL(amount,0)) FROM dbo.customer_payments p WHERE p.customer_id=a.CustomerId),0)
            - ISNULL((
                SELECT SUM(CASE WHEN ISNULL(adjustment_type,N''DISCOUNT'')=N''INCREASE''
                                THEN -ISNULL(amount,0) ELSE ISNULL(amount,0) END)
                FROM dbo.customer_debt_adjustments d WHERE d.customer_id=a.CustomerId
            ),0) AS CurrentDebt
        ) debt
        ORDER BY a.TotalRevenue DESC,a.CustomerName ASC;
    END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Report_GetRevenueByCashier
        @FromDate DATETIME,
        @ToDate DATETIME
    AS
    BEGIN
        SET NOCOUNT ON;
        SELECT ISNULL(c.name,N''Admin'') AS CashierName,
               COUNT(o.order_id) AS TotalOrders,
               ISNULL(SUM(CASE WHEN ISNULL(o.order_type,N''SALE'')=N''RETURN''
                               THEN -ABS(ISNULL(o.paid_amount,0))
                               ELSE ABS(ISNULL(o.paid_amount,0)) END),0) AS TotalRevenue
        FROM dbo.orders o
        LEFT JOIN dbo.employees c ON o.cashier_id=c.employee_id
        WHERE o.order_date BETWEEN @FromDate AND @ToDate
          AND ISNULL(o.status,N'''') IN (N''Completed'',N''Paid'',N''Partial'')
        GROUP BY c.name
        ORDER BY TotalRevenue DESC;
    END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Report_GetRevenueBySalesperson
        @FromDate DATETIME,
        @ToDate DATETIME
    AS
    BEGIN
        SET NOCOUNT ON;
        SELECT ISNULL(e.name,N''Không xác định'') AS EmployeeName,
               COUNT(o.order_id) AS TotalOrders,
               ISNULL(SUM(CASE WHEN ISNULL(o.order_type,N''SALE'')=N''RETURN''
                               THEN -ABS(ISNULL(o.final_amount,0))
                               ELSE ABS(ISNULL(o.final_amount,0)) END),0) AS TotalRevenue
        FROM dbo.orders o
        LEFT JOIN dbo.employees e ON o.employee_id=e.employee_id
        WHERE o.order_date BETWEEN @FromDate AND @ToDate
          AND ISNULL(o.status,N'''') IN (N''Completed'',N''Paid'',N''Partial'')
        GROUP BY e.name
        ORDER BY TotalRevenue DESC;
    END';

    IF @OwnTransaction = 1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @OwnTransaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION CustomerReportingFollowup;
    THROW;
END CATCH;
