/*
  MigrationId: 20260909_inventory_movement_partial

  Includes posted partial-payment sales and returns in the inventory-movement
  report.  It changes only dbo.Report_GetInventoryMovement; no transactional
  data, stock balance, invoice, or cashbook entry is modified.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
   OR OBJECT_ID(N'dbo.orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.order_items', N'U') IS NULL
   OR OBJECT_ID(N'dbo.products', N'U') IS NULL
    THROW 51451, N'Chọn đúng database HoaTran POS trước khi chạy migration báo cáo biến động kho.', 1;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.Report_GetInventoryMovement
    @FromDate DATETIME,
    @ToDate   DATETIME,
    @Keyword  NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME;
    DECLARE @EndDateExclusive DATETIME;

    SET @StartDate = CONVERT(DATE, @FromDate);
    SET @EndDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));
    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    ;WITH Movements AS
    (
        SELECT
            id.product_id,
            i.import_date AS movement_date,
            CAST(ISNULL(id.base_quantity, id.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(id.total, ISNULL(id.import_price, 0) * ISNULL(id.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'PURCHASE_IN' AS movement_type
        FROM dbo.import_details id
        INNER JOIN dbo.imports i ON i.import_id = id.import_id
        WHERE ISNULL(i.status, N'') IN (N'Completed', N'Paid')
          AND i.import_date IS NOT NULL
          AND id.product_id IS NOT NULL

        UNION ALL

        SELECT
            prd.product_id,
            pr.return_date AS movement_date,
            -CAST(COALESCE(NULLIF(prd.base_quantity, 0), prd.quantity * ISNULL(NULLIF(prd.unit_conversion_to_base, 0), 1)) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(prd.total, ISNULL(prd.import_price, 0) * ISNULL(prd.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SUPPLIER_RETURN_OUT' AS movement_type
        FROM dbo.purchase_return_details prd
        INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
        WHERE ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
          AND pr.return_date IS NOT NULL
          AND prd.product_id IS NOT NULL

        UNION ALL

        -- Posted partial-payment sales have already reduced stock, so they
        -- must be reported together with fully paid/completed sales.
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            -CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SALES_OUT' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed', N'Partial')
          AND ISNULL(o.order_type, N'') <> N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND ISNULL(oi.quantity, 0) > 0

        UNION ALL

        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3))) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'RETURN_IN' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed', N'Partial')
          AND ISNULL(o.order_type, N'') = N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL

        UNION ALL

        SELECT
            icd.product_id,
            ic.check_date AS movement_date,
            CAST(icd.difference AS DECIMAL(18, 3)) AS qty,
            CAST(0 AS DECIMAL(18, 0)) AS amount,
            N'STOCKTAKE' AS movement_type
        FROM dbo.inventory_check_details icd
        INNER JOIN dbo.inventory_checks ic ON ic.check_id = icd.check_id
        WHERE ic.check_date IS NOT NULL
          AND icd.product_id IS NOT NULL
          AND ISNULL(icd.difference, 0) <> 0

        UNION ALL

        SELECT
            b.product_id,
            m.created_at,
            CAST(m.quantity_change AS DECIMAL(18, 3)),
            CAST(0 AS DECIMAL(18, 0)),
            N'EXPIRED_WRITE_OFF'
        FROM dbo.batch_inventory_movements m
        INNER JOIN dbo.product_batches b ON b.batch_id = m.batch_id
        WHERE m.movement_type = N'EXPIRED_WRITE_OFF'
          AND m.quantity_change < 0
    ),
    PeriodSummary AS
    (
        SELECT
            product_id,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'         AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS PurchaseInQty,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SupplierReturnOutQty,
            SUM(CASE WHEN movement_type = N'SALES_OUT'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SalesOutQty,
            SUM(CASE WHEN movement_type = N'RETURN_IN'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS ReturnInQty,
            SUM(CASE WHEN movement_type = N'EXPIRED_WRITE_OFF'   AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS ExpiredWriteOffQty,
            SUM(CASE WHEN movement_type = N'STOCKTAKE'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS StocktakeAdjustQty,
            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'         AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SupplierReturnOutValue,
            SUM(CASE WHEN movement_type = N'SALES_OUT'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue
        FROM Movements
        GROUP BY product_id
    ),
    AfterPeriodSummary AS
    (
        SELECT product_id, SUM(qty) AS NetAfterPeriodQty
        FROM Movements
        WHERE movement_date >= @EndDateExclusive
        GROUP BY product_id
    )
    SELECT
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        ISNULL(p.barcode, N'') AS Barcode,
        p.product_name AS ProductName,
        ISNULL(c.category_name, N'') AS CategoryName,
        ISNULL(u.unit_name, N'') AS UnitName,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) - ISNULL(ps.NetPeriodQty, 0) AS DECIMAL(18, 3)) AS OpeningStock,
        CAST(ISNULL(ps.PurchaseInQty, 0) AS DECIMAL(18, 3)) AS PurchaseInQty,
        CAST(ISNULL(ps.ReturnInQty, 0) AS DECIMAL(18, 3)) AS ReturnInQty,
        CAST(ISNULL(ps.SupplierReturnOutQty, 0) AS DECIMAL(18, 3)) AS SupplierReturnOutQty,
        CAST(ISNULL(ps.ExpiredWriteOffQty, 0) AS DECIMAL(18, 3)) AS ExpiredWriteOffQty,
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
      AND
      (
          @Keyword = N''
          OR p.product_code LIKE N'%' + @Keyword + N'%'
          OR ISNULL(p.barcode, N'') LIKE N'%' + @Keyword + N'%'
          OR p.product_name LIKE N'%' + @Keyword + N'%'
      )
    ORDER BY p.product_code, p.product_name;
END;
GO
