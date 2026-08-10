/* Hotfix 2026-08-10
   Report: increase top selling products from 10 to 50 for the product tab.
   Safe to run multiple times. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.Report_TopSellingProducts', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Report_TopSellingProducts @FromDate DATETIME, @ToDate DATETIME AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Report_TopSellingProducts]
    @FromDate DATETIME,
    @ToDate   DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 50
        p.product_code AS ProductCode,
        p.product_name AS ProductName,
        SUM(od.quantity) AS TotalQuantity,
        SUM(od.quantity * od.unit_price) AS TotalRevenue
    FROM dbo.order_items od
    INNER JOIN dbo.Orders o ON od.order_id = o.order_id
    INNER JOIN dbo.Products p ON od.product_id = p.product_id
    WHERE o.order_date >= @FromDate
      AND o.order_date <= @ToDate
      AND o.status IN (N'Completed', N'Paid')
    GROUP BY p.product_code, p.product_name
    ORDER BY TotalQuantity DESC;
END
GO
