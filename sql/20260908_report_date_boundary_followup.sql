/*
  MigrationId: 20260908_report_date_boundary_followup
  Run after 20260908_customer_reporting_followup.sql.

  Normalizes an end-date with a time component to its calendar date before
  adding one day. This prevents Cashbook and Top Customer reports from
  including records from the following day.
  Does not modify transactional business data; rerunnable in an updater-owned
  transaction.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
   OR OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NULL
   OR OBJECT_ID(N'dbo.orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customer_payments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customer_debt_adjustments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.repair_orders', N'U') IS NULL
    THROW 51441, N'Chọn đúng database HoaTran POS đã chạy các migration nghiệp vụ và báo cáo trước đó.', 1;

DECLARE @OwnTransaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
BEGIN TRY
    IF @OwnTransaction = 1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION ReportDateBoundaryFollowup;

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Cashbook_GetSummary
        @FromDate DATETIME = NULL,
        @ToDate DATETIME = NULL
    AS
    BEGIN
        SET NOCOUNT ON;

        DECLARE @ToDateExclusive DATETIME;
        IF @ToDate IS NOT NULL
            SET @ToDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));

        SELECT
            ISNULL(SUM(CASE WHEN entry_type = N''IN'' THEN amount ELSE 0 END), 0) AS TotalIn,
            ISNULL(SUM(CASE WHEN entry_type = N''OUT'' THEN amount ELSE 0 END), 0) AS TotalOut,
            ISNULL(SUM(CASE WHEN entry_type = N''IN'' THEN amount ELSE -amount END), 0) AS Balance,
            COUNT(1) AS EntryCount
        FROM dbo.cashbook_entries
        WHERE is_deleted = 0
          AND (@FromDate IS NULL OR entry_date >= @FromDate)
          AND (@ToDateExclusive IS NULL OR entry_date < @ToDateExclusive);
    END';

    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Cashbook_Search
        @FromDate DATETIME = NULL,
        @ToDate DATETIME = NULL,
        @Type NVARCHAR(10) = NULL,
        @Keyword NVARCHAR(200) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;

        SET @Type = NULLIF(UPPER(LTRIM(RTRIM(ISNULL(@Type, N'''')))), N'''');
        SET @Keyword = NULLIF(LTRIM(RTRIM(ISNULL(@Keyword, N''''))), N'''');

        DECLARE @ToDateExclusive DATETIME;
        IF @ToDate IS NOT NULL
            SET @ToDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));

        SELECT
            entry_id AS EntryId,
            entry_code AS EntryCode,
            entry_date AS EntryDate,
            entry_type AS EntryType,
            category_id AS CategoryId,
            category_name AS CategoryName,
            amount AS Amount,
            payment_method AS PaymentMethod,
            description AS Description,
            reference_code AS ReferenceCode,
            created_by AS CreatedBy,
            created_at AS CreatedAt,
            updated_at AS UpdatedAt
        FROM dbo.cashbook_entries
        WHERE is_deleted = 0
          AND (@FromDate IS NULL OR entry_date >= @FromDate)
          AND (@ToDateExclusive IS NULL OR entry_date < @ToDateExclusive)
          AND (@Type IS NULL OR entry_type = @Type)
          AND
          (
              @Keyword IS NULL
              OR entry_code LIKE N''%'' + @Keyword + N''%''
              OR category_name LIKE N''%'' + @Keyword + N''%''
              OR payment_method LIKE N''%'' + @Keyword + N''%''
              OR reference_code LIKE N''%'' + @Keyword + N''%''
              OR description LIKE N''%'' + @Keyword + N''%''
              OR created_by LIKE N''%'' + @Keyword + N''%''
          )
        ORDER BY entry_date DESC, entry_id DESC;
    END';

    -- Preserve the debt/reporting formula from the prior customer-reporting
    -- migration; only the end-date boundary changes here.
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.Customer_GetTop
        @TopCount INT = 20,
        @FromDate DATETIME = NULL,
        @ToDate DATETIME = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        IF @TopCount IS NULL OR @TopCount <= 0 SET @TopCount = 20;

        DECLARE @ToDateExclusive DATETIME;
        IF @ToDate IS NOT NULL
            SET @ToDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));

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
                CASE WHEN ISNULL(o.order_type, N'''') = N''RETURN''
                     THEN -ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0)))
                     ELSE ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0))) END AS NetRevenue,
                CASE WHEN ISNULL(o.order_type, N'''') = N''RETURN''
                     THEN -ISNULL(costs.CostOfGoodsSold, 0)
                     ELSE ISNULL(costs.CostOfGoodsSold, 0) END AS NetCost,
                CASE WHEN ISNULL(o.order_type, N'''') = N''RETURN'' THEN 0 ELSE 1 END AS SalesOrderCount
            FROM dbo.customers c
            INNER JOIN dbo.orders o ON c.customer_id = o.customer_id
            OUTER APPLY
            (
                SELECT SUM(ISNULL(oi.cost_price, ISNULL(p.import_price, 0))
                           * ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18,3)))) AS CostOfGoodsSold
                FROM dbo.order_items oi
                LEFT JOIN dbo.products p ON p.product_id = oi.product_id
                WHERE oi.order_id = o.order_id
            ) costs
            WHERE (@FromDate IS NULL OR o.order_date >= @FromDate)
              AND (@ToDateExclusive IS NULL OR o.order_date < @ToDateExclusive)
              AND ISNULL(o.status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'', N''Pending'')
        )
        SELECT TOP (@TopCount)
            co.CustomerId, co.CustomerName, co.Phone, co.Email, co.Address, co.Points, co.CreatedAt,
            SUM(co.SalesOrderCount) AS TotalOrders,
            ISNULL(SUM(co.NetRevenue), 0) AS TotalRevenue,
            ISNULL(SUM(co.NetCost), 0) AS TotalCost,
            ISNULL(SUM(co.NetRevenue - co.NetCost), 0) AS GrossProfit,
            CASE WHEN ISNULL(SUM(co.NetRevenue), 0) = 0 THEN 0
                 ELSE ISNULL(SUM(co.NetRevenue - co.NetCost), 0) * 100.0 / NULLIF(SUM(co.NetRevenue), 0) END AS ProfitMargin,
            MIN(co.OrderDate) AS FirstOrderDate,
            MAX(co.OrderDate) AS LastOrderDate,
            ISNULL((
                SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
                FROM dbo.orders o
                WHERE o.customer_id = co.CustomerId
                  AND ISNULL(o.status, N'''') NOT IN (N''Cancelled'', N''Canceled'', N''Đã hủy'', N''Hủy'', N''Pending'')
            ), 0)
            + ISNULL((
                SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
                FROM dbo.repair_orders ro
                WHERE ro.customer_id = co.CustomerId
                  AND ISNULL(ro.status, N'''') NOT IN (N''CANCELLED'', N''DECLINED'', N''UNREPAIRABLE'')
                  AND (ISNULL(ro.quote_status, N'''') = N''APPROVED'' OR ISNULL(ro.paid_amount, 0) > 0)
            ), 0)
            - ISNULL((SELECT SUM(ISNULL(amount, 0)) FROM dbo.customer_payments p WHERE p.customer_id = co.CustomerId), 0)
            - ISNULL((
                SELECT SUM(CASE WHEN ISNULL(adjustment_type, N''DISCOUNT'') = N''INCREASE''
                                THEN -ISNULL(amount, 0) ELSE ISNULL(amount, 0) END)
                FROM dbo.customer_debt_adjustments a WHERE a.customer_id = co.CustomerId
            ), 0) AS CurrentDebt
        FROM CustomerOrders co
        GROUP BY co.CustomerId, co.CustomerName, co.Phone, co.Email, co.Address, co.Points, co.CreatedAt
        ORDER BY TotalRevenue DESC;
    END';

    IF @OwnTransaction = 1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @OwnTransaction = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION ReportDateBoundaryFollowup;
    THROW;
END CATCH;
