/* Hotfix 2026-08-09
   Add customer-level cost, gross profit, and profit margin to Customer_GetTop.
   Safe to run on an existing database. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.Customer_GetTop', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Customer_GetTop @TopCount INT = 20, @FromDate DATETIME = NULL, @ToDate DATETIME = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Customer_GetTop]
    @TopCount INT = 20,
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
            CASE
                WHEN ISNULL(o.order_type, N'') = N'RETURN'
                    THEN -1 * ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0)))
                ELSE ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0)))
            END AS NetRevenue,
            CASE
                WHEN ISNULL(o.order_type, N'') = N'RETURN'
                    THEN -1 * ISNULL(costs.CostOfGoodsSold, 0)
                ELSE ISNULL(costs.CostOfGoodsSold, 0)
            END AS NetCost,
            CASE WHEN ISNULL(o.order_type, N'') = N'RETURN' THEN 0 ELSE 1 END AS SalesOrderCount
        FROM dbo.customers c
        INNER JOIN dbo.orders o ON c.customer_id = o.customer_id
        OUTER APPLY
        (
            SELECT
                SUM(
                    ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0))
                    * ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18,3)))
                ) AS CostOfGoodsSold
            FROM dbo.order_items oi
            LEFT JOIN dbo.products p ON p.product_id = oi.product_id
            WHERE oi.order_id = o.order_id
        ) costs
        WHERE
            (@FromDate IS NULL OR o.order_date >= @FromDate)
            AND (@ToDate IS NULL OR o.order_date < DATEADD(DAY, 1, @ToDate))
            AND ISNULL(o.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    )
    SELECT TOP (@TopCount)
        co.CustomerId,
        co.CustomerName,
        co.Phone,
        co.Email,
        co.Address,
        co.Points,
        co.CreatedAt,
        SUM(co.SalesOrderCount) AS TotalOrders,
        ISNULL(SUM(co.NetRevenue), 0) AS TotalRevenue,
        ISNULL(SUM(co.NetCost), 0) AS TotalCost,
        ISNULL(SUM(co.NetRevenue - co.NetCost), 0) AS GrossProfit,
        CASE
            WHEN ISNULL(SUM(co.NetRevenue), 0) = 0 THEN 0
            ELSE ISNULL(SUM(co.NetRevenue - co.NetCost), 0) * 100.0 / NULLIF(SUM(co.NetRevenue), 0)
        END AS ProfitMargin,
        MIN(co.OrderDate) AS FirstOrderDate,
        MAX(co.OrderDate) AS LastOrderDate,
        (
            ISNULL((
                SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
                FROM dbo.orders
                WHERE customer_id = co.CustomerId
                  AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
                  AND ISNULL(order_type, N'') <> N'RETURN'
            ), 0)
            -
            ISNULL((
                SELECT SUM(ISNULL(amount, 0))
                FROM dbo.customer_payments
                WHERE customer_id = co.CustomerId
            ), 0)
        ) AS CurrentDebt
    FROM CustomerOrders co
    GROUP BY
        co.CustomerId,
        co.CustomerName,
        co.Phone,
        co.Email,
        co.Address,
        co.Points,
        co.CreatedAt
    ORDER BY TotalRevenue DESC;
END
GO

IF OBJECT_ID(N'dbo.Report_GetCustomerProfitByCustomer', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Report_GetCustomerProfitByCustomer @FromDate DATETIME, @ToDate DATETIME, @TopCount INT = 20 AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Report_GetCustomerProfitByCustomer]
    @FromDate DATETIME,
    @ToDate DATETIME,
    @TopCount INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CustomerOrders AS
    (
        SELECT
            c.customer_id AS CustomerId,
            ISNULL(NULLIF(LTRIM(RTRIM(c.customer_code)), N''), N'KH' + RIGHT(N'000000' + CAST(c.customer_id AS NVARCHAR(20)), 6)) AS CustomerCode,
            ISNULL(c.name, N'') AS CustomerName,
            ISNULL(c.phone, N'') AS Phone,
            ISNULL(c.address, N'') AS Address,
            ISNULL(c.points, 0) AS Points,
            o.order_id AS OrderId,
            o.order_date AS OrderDate,
            CASE
                WHEN ISNULL(o.order_type, N'') = N'RETURN'
                    THEN -1 * ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0)))
                ELSE ABS(ISNULL(o.final_amount, ISNULL(o.total_amount, 0)))
            END AS NetRevenue,
            CASE
                WHEN ISNULL(o.order_type, N'') = N'RETURN'
                    THEN -1 * ISNULL(costs.CostOfGoodsSold, 0)
                ELSE ISNULL(costs.CostOfGoodsSold, 0)
            END AS NetCost,
            CASE WHEN ISNULL(o.order_type, N'') = N'RETURN' THEN 0 ELSE 1 END AS SalesOrderCount
        FROM dbo.customers c
        INNER JOIN dbo.orders o ON c.customer_id = o.customer_id
        OUTER APPLY
        (
            SELECT
                SUM(
                    ISNULL(NULLIF(oi.cost_price, 0), ISNULL(p.import_price, 0))
                    * ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18,3)))
                ) AS CostOfGoodsSold
            FROM dbo.order_items oi
            LEFT JOIN dbo.products p ON p.product_id = oi.product_id
            WHERE oi.order_id = o.order_id
        ) costs
        WHERE o.order_date BETWEEN @FromDate AND @ToDate
          AND ISNULL(o.status, N'') IN (N'Completed', N'Paid', N'Partial')
    ),
    Aggregated AS
    (
        SELECT TOP (@TopCount)
            co.CustomerId,
            co.CustomerCode,
            co.CustomerName,
            co.Phone,
            co.Address,
            co.Points,
            SUM(co.SalesOrderCount) AS TotalOrders,
            ISNULL(SUM(co.NetRevenue), 0) AS TotalRevenue,
            ISNULL(SUM(co.NetCost), 0) AS TotalCost,
            ISNULL(SUM(co.NetRevenue - co.NetCost), 0) AS GrossProfit,
            CASE
                WHEN ISNULL(SUM(co.NetRevenue), 0) = 0 THEN 0
                ELSE ISNULL(SUM(co.NetRevenue - co.NetCost), 0) * 100.0 / NULLIF(SUM(co.NetRevenue), 0)
            END AS ProfitMargin,
            MIN(co.OrderDate) AS FirstOrderDate,
            MAX(co.OrderDate) AS LastOrderDate
        FROM CustomerOrders co
        GROUP BY
            co.CustomerId,
            co.CustomerCode,
            co.CustomerName,
            co.Phone,
            co.Address,
            co.Points
        ORDER BY TotalRevenue DESC
    )
    SELECT
        a.CustomerId,
        a.CustomerCode,
        a.CustomerName,
        a.Phone,
        a.Address,
        CASE WHEN ISNULL(debt.CurrentDebt, 0) > 0 THEN ISNULL(debt.CurrentDebt, 0) ELSE 0 END AS CurrentDebt,
        a.Points,
        a.TotalOrders,
        a.TotalRevenue,
        a.TotalCost,
        a.GrossProfit,
        a.ProfitMargin,
        a.FirstOrderDate,
        a.LastOrderDate
    FROM Aggregated a
    OUTER APPLY
    (
        SELECT
            ISNULL((
                SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
                FROM dbo.orders
                WHERE customer_id = a.CustomerId
                  AND ISNULL(status, N'') IN (N'Completed', N'Partial')
                  AND ISNULL(order_type, N'') <> N'RETURN'
                  AND ISNULL(final_amount, 0) > ISNULL(paid_amount, 0)
            ), 0)
            -
            ISNULL((
                SELECT SUM(ISNULL(amount, 0))
                FROM dbo.customer_payments
                WHERE customer_id = a.CustomerId
            ), 0) AS CurrentDebt
    ) debt
    ORDER BY a.TotalRevenue DESC, a.CustomerName ASC;
END
GO
