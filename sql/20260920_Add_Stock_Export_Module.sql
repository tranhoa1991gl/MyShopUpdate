/*
    HoaTran POS - Phân hệ Xuất kho (Stock Export):
    - Xuất dùng nội bộ (INTERNAL_USE)
    - Xuất hủy (STOCK_DISPOSAL)

    1. Bảng dbo.stock_exports (Header)
    2. Bảng dbo.stock_export_details (Details)
    3. Cập nhật Stored Procedure dbo.Report_GetInventoryMovement để ghi nhận biến động Xuất dùng nội bộ và Xuất hủy.

    Script an toàn khi chạy lại nhiều lần (idempotent).
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Bảng Phiếu xuất kho (Header)
IF OBJECT_ID(N'dbo.stock_exports', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.stock_exports
    (
        export_id          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_stock_exports PRIMARY KEY,
        export_code        VARCHAR(30) NOT NULL CONSTRAINT UQ_stock_exports_code UNIQUE,
        export_type        VARCHAR(30) NOT NULL, -- 'INTERNAL_USE', 'STOCK_DISPOSAL'
        export_date        DATETIME NOT NULL CONSTRAINT DF_stock_exports_date DEFAULT (GETDATE()),
        status             NVARCHAR(20) NOT NULL CONSTRAINT DF_stock_exports_status DEFAULT (N'Draft'), -- Draft, Completed, Cancelled
        total_quantity     DECIMAL(18, 3) NOT NULL CONSTRAINT DF_stock_exports_qty DEFAULT (0),
        total_cost_value   DECIMAL(18, 2) NOT NULL CONSTRAINT DF_stock_exports_cost DEFAULT (0),
        reason             NVARCHAR(200) NULL,
        note               NVARCHAR(500) NULL,
        created_by         INT NOT NULL,
        created_at         DATETIME NOT NULL CONSTRAINT DF_stock_exports_created DEFAULT (GETDATE()),
        completed_at       DATETIME NULL,
        cancelled_at       DATETIME NULL,
        cancelled_by       INT NULL,
        cancel_reason      NVARCHAR(500) NULL
    );

    CREATE NONCLUSTERED INDEX IX_stock_exports_type_date ON dbo.stock_exports(export_type, export_date);
    CREATE NONCLUSTERED INDEX IX_stock_exports_status ON dbo.stock_exports(status);
END;
GO

-- 2. Bảng Chi tiết phiếu xuất kho (Details)
IF OBJECT_ID(N'dbo.stock_export_details', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.stock_export_details
    (
        detail_id               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_stock_export_details PRIMARY KEY,
        export_id               INT NOT NULL,
        product_id              INT NOT NULL,
        variant_id              INT NULL,
        unit_id                 INT NULL,
        unit_conversion_to_base DECIMAL(18, 6) NOT NULL CONSTRAINT DF_stock_exp_det_conv DEFAULT (1),
        quantity                DECIMAL(18, 3) NOT NULL,
        base_quantity           DECIMAL(18, 3) NOT NULL CONSTRAINT DF_stock_exp_det_base_qty DEFAULT (0),
        cost_price              DECIMAL(18, 2) NOT NULL CONSTRAINT DF_stock_exp_det_cost DEFAULT (0),
        total_cost              DECIMAL(18, 2) NOT NULL CONSTRAINT DF_stock_exp_det_total DEFAULT (0),
        note                    NVARCHAR(255) NULL,
        CONSTRAINT FK_stock_exp_det_export FOREIGN KEY (export_id) REFERENCES dbo.stock_exports(export_id) ON DELETE CASCADE,
        CONSTRAINT FK_stock_exp_det_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_stock_exp_det_unit FOREIGN KEY (unit_id) REFERENCES dbo.Units(unit_id)
    );

    CREATE NONCLUSTERED INDEX IX_stock_exp_det_export ON dbo.stock_export_details(export_id);
    CREATE NONCLUSTERED INDEX IX_stock_exp_det_product ON dbo.stock_export_details(product_id, variant_id);
END;
GO

-- 3. Cập nhật Stored Procedure dbo.Report_GetInventoryMovement
IF OBJECT_ID(N'dbo.Report_GetInventoryMovement', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE [dbo].[Report_GetInventoryMovement] AS BEGIN SET NOCOUNT ON; END;');
END;
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
        -- 1. Nhập hàng từ Nhà cung cấp
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

        -- 2. Trả hàng Nhà cung cấp
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

        -- 3. Bán hàng Combo (Linh kiện cấu thành)
        SELECT
            component_product_id,
            movement_date,
            qty,
            amount,
            movement_type
        FROM ComboSnapshotMovements
        WHERE movement_type = N'SALES_OUT'

        UNION ALL

        -- 4. Bán hàng thường
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

        -- 5. Khách trả hàng Combo
        SELECT
            component_product_id,
            movement_date,
            qty,
            amount,
            movement_type
        FROM ComboSnapshotMovements
        WHERE movement_type = N'RETURN_IN'

        UNION ALL

        -- 6. Khách trả hàng thường
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

        -- 7. Kiểm kê kho (Chênh lệch)
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

        -- 8. Hủy hàng hết hạn theo Lô
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

        UNION ALL

        -- 9. Biến động Sản xuất & Hủy sản xuất (Manufacturing Stock Movements)
        SELECT
            msm.product_id,
            msm.movement_date,
            CAST(msm.quantity_change AS DECIMAL(18, 3)) AS qty,
            CAST(msm.total_amount AS DECIMAL(18, 0)) AS amount,
            msm.movement_type
        FROM dbo.manufacturing_stock_movements msm
        WHERE msm.movement_date IS NOT NULL

        UNION ALL

        -- 10. Xuất dùng nội bộ & Xuất hủy
        SELECT
            sed.product_id,
            se.export_date AS movement_date,
            -CAST(sed.base_quantity AS DECIMAL(18, 3)) AS qty,
            CAST(sed.total_cost AS DECIMAL(18, 0)) AS amount,
            CASE WHEN se.export_type = 'INTERNAL_USE' THEN N'INTERNAL_USE_OUT' ELSE N'STOCK_DISPOSAL_OUT' END AS movement_type
        FROM dbo.stock_export_details sed
        INNER JOIN dbo.stock_exports se ON se.export_id = sed.export_id
        WHERE (se.status = N'Completed' OR (se.status = N'Cancelled' AND se.completed_at IS NOT NULL))
          AND se.export_date IS NOT NULL
          AND sed.product_id IS NOT NULL

        UNION ALL

        -- 11. Hủy phiếu xuất dùng nội bộ & Xuất hủy (Hoàn kho)
        SELECT
            sed.product_id,
            se.cancelled_at AS movement_date,
            CAST(sed.base_quantity AS DECIMAL(18, 3)) AS qty,
            CAST(sed.total_cost AS DECIMAL(18, 0)) AS amount,
            CASE WHEN se.export_type = 'INTERNAL_USE' THEN N'INTERNAL_USE_CANCEL_IN' ELSE N'STOCK_DISPOSAL_CANCEL_IN' END AS movement_type
        FROM dbo.stock_export_details sed
        INNER JOIN dbo.stock_exports se ON se.export_id = sed.export_id
        WHERE se.status = N'Cancelled'
          AND se.completed_at IS NOT NULL
          AND se.cancelled_at IS NOT NULL
          AND sed.product_id IS NOT NULL
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
            -- Sản xuất: Nhập thành phẩm & Nhập hoàn trả NVL khi hủy phiếu
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_IN', N'MANUFACTURING_CANCEL_IN') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS ManufacturingInQty,
            -- Sản xuất: Xuất NVL sản xuất & Xuất thu hồi thành phẩm khi hủy phiếu
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_OUT', N'MANUFACTURING_CANCEL_OUT') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS ManufacturingOutQty,
            -- Xuất dùng nội bộ
            SUM(CASE WHEN movement_type = N'INTERNAL_USE_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) -
            SUM(CASE WHEN movement_type = N'INTERNAL_USE_CANCEL_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS InternalUseOutQty,
            -- Xuất hủy
            SUM(CASE WHEN movement_type = N'STOCK_DISPOSAL_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) -
            SUM(CASE WHEN movement_type = N'STOCK_DISPOSAL_CANCEL_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS DisposalOutQty,

            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'         AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SupplierReturnOutValue,
            SUM(CASE WHEN movement_type = N'SALES_OUT'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue,
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_IN', N'MANUFACTURING_CANCEL_IN') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS ManufacturingInValue,
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_OUT', N'MANUFACTURING_CANCEL_OUT') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS ManufacturingOutValue,
            -- Giá trị xuất dùng nội bộ
            SUM(CASE WHEN movement_type = N'INTERNAL_USE_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) -
            SUM(CASE WHEN movement_type = N'INTERNAL_USE_CANCEL_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS InternalUseCostValue,
            -- Giá trị xuất hủy
            SUM(CASE WHEN movement_type = N'STOCK_DISPOSAL_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) -
            SUM(CASE WHEN movement_type = N'STOCK_DISPOSAL_CANCEL_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS DisposalCostValue
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
        CAST(ISNULL(ps.ManufacturingInQty, 0) AS DECIMAL(18, 3)) AS ManufacturingInQty,
        CAST(ISNULL(ps.SupplierReturnOutQty, 0) AS DECIMAL(18, 3)) AS SupplierReturnOutQty,
        CAST(ISNULL(ps.StocktakeAdjustQty, 0) AS DECIMAL(18, 3)) AS StocktakeAdjustQty,
        CAST(ISNULL(ps.ExpiredWriteOffQty, 0) AS DECIMAL(18, 3)) AS ExpiredWriteOffQty,
        CAST(ISNULL(ps.InternalUseOutQty, 0) AS DECIMAL(18, 3)) AS InternalUseOutQty,
        CAST(ISNULL(ps.DisposalOutQty, 0) AS DECIMAL(18, 3)) AS DisposalOutQty,
        CAST(ISNULL(ps.ManufacturingOutQty, 0) AS DECIMAL(18, 3)) AS ManufacturingOutQty,
        CAST(ISNULL(ps.SalesOutQty, 0) AS DECIMAL(18, 3)) AS SalesOutQty,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) AS DECIMAL(18, 3)) AS ClosingStock,
        CAST(ISNULL(p.stock, 0) AS DECIMAL(18, 3)) AS CurrentStock,
        CAST(ISNULL(ps.PurchaseInValue, 0) AS DECIMAL(18, 0)) AS PurchaseInValue,
        CAST(ISNULL(ps.SupplierReturnOutValue, 0) AS DECIMAL(18, 0)) AS SupplierReturnOutValue,
        CAST(ISNULL(ps.ManufacturingInValue, 0) AS DECIMAL(18, 0)) AS ManufacturingInValue,
        CAST(ISNULL(ps.InternalUseCostValue, 0) AS DECIMAL(18, 0)) AS InternalUseCostValue,
        CAST(ISNULL(ps.DisposalCostValue, 0) AS DECIMAL(18, 0)) AS DisposalCostValue,
        CAST(ISNULL(ps.ManufacturingOutValue, 0) AS DECIMAL(18, 0)) AS ManufacturingOutValue,
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

PRINT N'Đã hoàn thành cấu hình CSDL cho phân hệ Xuất kho (Xuất dùng nội bộ & Xuất hủy) và cập nhật Báo cáo Xuất Nhập Tồn.';
GO
