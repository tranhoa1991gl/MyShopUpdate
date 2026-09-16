/*
    HoaTran POS - báo cáo xuất nhập tồn cho Combo / Đóng gói.

    Combo là hàng ảo. Báo cáo phải đưa số lượng xuất/nhập trả về đúng
    các linh kiện đã thực sự biến động, lấy từ snapshot lúc bán; không
    ghi thêm biến động ở sản phẩm Combo cha.

    Yêu cầu: bản nâng cấp Combo đã tạo dbo.order_item_combo_snapshots.
    Script có thể chạy lại an toàn.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.order_item_combo_snapshots', N'U') IS NULL
    THROW 51610, N'Thiếu bảng snapshot Combo. Hãy cập nhật tính năng Combo trước khi chạy bản vá báo cáo.', 1;

IF OBJECT_ID(N'dbo.Report_GetInventoryMovement', N'P') IS NULL
    THROW 51611, N'Không tìm thấy stored procedure báo cáo xuất nhập tồn để cập nhật.', 1;
GO

ALTER PROCEDURE [dbo].[Report_GetInventoryMovement]
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

    ;WITH ComboSnapshotSource AS
    (
        SELECT
            s.snapshot_id,
            s.order_id,
            s.order_item_id,
            s.component_product_id,
            o.order_date AS movement_date,
            CASE WHEN ISNULL(o.order_type, N'') = N'RETURN' THEN N'RETURN_IN' ELSE N'SALES_OUT' END AS movement_type,
            CAST(CASE WHEN ISNULL(o.order_type, N'') = N'RETURN'
                      THEN ABS(ISNULL(s.total_quantity, 0))
                      ELSE -ABS(ISNULL(s.total_quantity, 0)) END AS DECIMAL(18, 3)) AS movement_qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS parent_amount,
            CAST(ABS(ISNULL(s.total_quantity, 0)) * ISNULL(s.component_cost_price, 0) AS DECIMAL(38, 6)) AS component_cost_weight,
            SUM(CAST(ABS(ISNULL(s.total_quantity, 0)) * ISNULL(s.component_cost_price, 0) AS DECIMAL(38, 6)))
                OVER (PARTITION BY s.order_id, s.order_item_id) AS total_cost_weight,
            COUNT_BIG(*) OVER (PARTITION BY s.order_id, s.order_item_id) AS snapshot_count,
            ROW_NUMBER() OVER (PARTITION BY s.order_id, s.order_item_id ORDER BY s.snapshot_id) AS snapshot_sequence
        FROM dbo.order_item_combo_snapshots s
        INNER JOIN dbo.order_items oi ON oi.order_item_id = s.order_item_id
                                  AND oi.order_id = s.order_id
        INNER JOIN dbo.orders o ON o.order_id = s.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed', N'Partial')
          AND o.order_date IS NOT NULL
          AND s.component_product_id IS NOT NULL
          AND ISNULL(s.total_quantity, 0) <> 0
          AND
          (
              (ISNULL(o.order_type, N'') <> N'RETURN' AND ISNULL(oi.quantity, 0) > 0)
              OR ISNULL(o.order_type, N'') = N'RETURN'
          )
    ),
    ComboSnapshotMovements AS
    (
        SELECT
            component_product_id,
            movement_date,
            movement_qty AS qty,
            CAST(
                CASE
                    WHEN total_cost_weight > 0 THEN
                        CASE WHEN snapshot_sequence = 1 THEN
                            parent_amount - SUM(CASE WHEN snapshot_sequence > 1 THEN
                                ROUND(CONVERT(DECIMAL(38, 10), parent_amount) * component_cost_weight / NULLIF(total_cost_weight, 0), 0)
                                ELSE 0 END)
                                OVER (PARTITION BY order_id, order_item_id)
                        ELSE
                            ROUND(CONVERT(DECIMAL(38, 10), parent_amount) * component_cost_weight / NULLIF(total_cost_weight, 0), 0)
                        END
                    ELSE
                        CASE WHEN snapshot_sequence = 1 THEN
                            parent_amount - (snapshot_count - 1) * FLOOR(CONVERT(DECIMAL(38, 10), parent_amount) / NULLIF(snapshot_count, 0))
                        ELSE FLOOR(CONVERT(DECIMAL(38, 10), parent_amount) / NULLIF(snapshot_count, 0))
                        END
                END AS DECIMAL(18, 0)) AS amount,
            movement_type
        FROM ComboSnapshotSource
    ),
    Movements AS
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

        -- Combo is virtual: component quantities come from snapshots, while
        -- the virtual parent line is excluded below to prevent double count.
        -- Parent sale value is allocated by snapshot cost weight; the first
        -- row carries any rounding remainder so every invoice keeps its total.
        SELECT
            component_product_id,
            movement_date,
            qty,
            amount,
            movement_type
        FROM ComboSnapshotMovements
        WHERE movement_type = N'SALES_OUT'

        UNION ALL

        -- Preserve ordinary and pre-snapshot historical items. Items with a
        -- snapshot are deliberately excluded to avoid parent double count.
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            -CAST(ISNULL(oi.base_quantity, CASE WHEN ISNULL(oi.quantity, 0) < 0 THEN ISNULL(oi.quantity, 0) - ISNULL(oi.gift_quantity, 0) ELSE ISNULL(oi.quantity, 0) + ISNULL(oi.gift_quantity, 0) END) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SALES_OUT' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed', N'Partial')
          AND ISNULL(o.order_type, N'') <> N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND ISNULL(oi.quantity, 0) > 0
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.order_item_combo_snapshots s
              WHERE s.order_item_id = oi.order_item_id
                AND s.order_id = oi.order_id
          )

        UNION ALL

        -- A customer return restores the exact components from its immutable
        -- return snapshot. Value allocation follows the source sale formula.
        SELECT
            component_product_id,
            movement_date,
            qty,
            amount,
            movement_type
        FROM ComboSnapshotMovements
        WHERE movement_type = N'RETURN_IN'

        UNION ALL

        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            ABS(CAST(ISNULL(oi.base_quantity, CASE WHEN ISNULL(oi.quantity, 0) < 0 THEN ISNULL(oi.quantity, 0) - ISNULL(oi.gift_quantity, 0) ELSE ISNULL(oi.quantity, 0) + ISNULL(oi.gift_quantity, 0) END) AS DECIMAL(18, 3))) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'RETURN_IN' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed', N'Partial')
          AND ISNULL(o.order_type, N'') = N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.order_item_combo_snapshots s
              WHERE s.order_item_id = oi.order_item_id
                AND s.order_id = oi.order_id
          )

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
      AND ISNULL(p.is_combo, 0) = 0
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

PRINT N'Đã cập nhật báo cáo xuất nhập tồn để hạch toán Combo theo linh kiện thực tế.';
GO
