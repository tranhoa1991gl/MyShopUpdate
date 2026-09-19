/*
    HoaTran POS - Phân hệ Sản xuất (Manufacturing).
    - Tạo bảng định mức nguyên vật liệu sản xuất: dbo.product_bom_items
    - Tạo bảng phiếu sản xuất: dbo.manufacturing_orders
    - Tạo bảng chi tiết nguyên vật liệu tiêu hao: dbo.manufacturing_order_details
    - Tạo bảng lưu vết biến động thẻ kho: dbo.manufacturing_stock_movements
    - Cập nhật Stored Procedure dbo.Report_GetInventoryMovement để tích hợp biến động sản xuất và hủy sản xuất.

    Script an toàn khi chạy lại nhiều lần (idempotent).
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Bảng định mức nguyên vật liệu sản xuất (BOM - Bill of Materials)
IF OBJECT_ID(N'dbo.product_bom_items', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_bom_items
    (
        bom_item_id          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_bom_items PRIMARY KEY,
        product_id           INT NOT NULL,
        variant_id           INT NULL,
        component_product_id INT NOT NULL,
        component_variant_id INT NULL,
        component_unit_id    INT NULL,
        unit_conversion_to_base DECIMAL(18, 6) NOT NULL CONSTRAINT DF_bom_item_conv DEFAULT (1),
        quantity             DECIMAL(18, 3) NOT NULL CONSTRAINT DF_bom_item_qty DEFAULT (1),
        note                 NVARCHAR(255) NULL,
        created_at           DATETIME NOT NULL CONSTRAINT DF_bom_item_created DEFAULT (GETDATE()),
        CONSTRAINT FK_bom_parent FOREIGN KEY (product_id) REFERENCES dbo.products(product_id) ON DELETE CASCADE,
        CONSTRAINT FK_bom_component FOREIGN KEY (component_product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_bom_unit FOREIGN KEY (component_unit_id) REFERENCES dbo.Units(unit_id),
        CONSTRAINT CHK_bom_no_self CHECK (product_id <> component_product_id OR (product_id = component_product_id AND variant_id IS NOT NULL AND component_variant_id IS NOT NULL AND variant_id <> component_variant_id)),
        CONSTRAINT CHK_bom_quantity_positive CHECK (quantity > 0)
    );

    CREATE NONCLUSTERED INDEX IX_bom_parent ON dbo.product_bom_items(product_id, variant_id);
    CREATE NONCLUSTERED INDEX IX_bom_component ON dbo.product_bom_items(component_product_id, component_variant_id);
END
ELSE
BEGIN
    IF COL_LENGTH(N'dbo.product_bom_items', N'component_unit_id') IS NULL
        ALTER TABLE dbo.product_bom_items ADD component_unit_id INT NULL;

    IF COL_LENGTH(N'dbo.product_bom_items', N'unit_conversion_to_base') IS NULL
        ALTER TABLE dbo.product_bom_items ADD unit_conversion_to_base DECIMAL(18, 6) NOT NULL CONSTRAINT DF_bom_item_conv DEFAULT (1);
END;
GO

-- 2. Bảng Phiếu sản xuất (Header)
IF OBJECT_ID(N'dbo.manufacturing_orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.manufacturing_orders
    (
        order_id             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_manufacturing_orders PRIMARY KEY,
        order_code           VARCHAR(30) NOT NULL CONSTRAINT UQ_mfg_orders_code UNIQUE,
        product_id           INT NOT NULL,
        variant_id           INT NULL,
        quantity             DECIMAL(18, 3) NOT NULL,
        production_date      DATETIME NOT NULL CONSTRAINT DF_mfg_orders_prod_date DEFAULT (GETDATE()),
        status               NVARCHAR(20) NOT NULL CONSTRAINT DF_mfg_orders_status DEFAULT (N'Draft'), -- Draft, Completed, Cancelled
        total_material_cost  DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_orders_mat_cost DEFAULT (0),
        unit_cost            DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_orders_unit_cost DEFAULT (0),
        product_cost_before  DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_orders_cost_before DEFAULT (0),
        product_stock_before DECIMAL(18, 3) NOT NULL CONSTRAINT DF_mfg_orders_stock_before DEFAULT (0),
        auto_deduct_sub      BIT NOT NULL CONSTRAINT DF_mfg_orders_auto_deduct DEFAULT (0),
        note                 NVARCHAR(500) NULL,
        created_by           INT NOT NULL,
        created_at           DATETIME NOT NULL CONSTRAINT DF_mfg_orders_created DEFAULT (GETDATE()),
        completed_at         DATETIME NULL,
        cancelled_at         DATETIME NULL,
        cancelled_by         INT NULL,
        cancel_reason        NVARCHAR(500) NULL,
        CONSTRAINT FK_mfg_orders_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id)
    );

    CREATE NONCLUSTERED INDEX IX_mfg_orders_prod_date ON dbo.manufacturing_orders(production_date);
    CREATE NONCLUSTERED INDEX IX_mfg_orders_status ON dbo.manufacturing_orders(status);
END;
GO

-- 3. Bảng Chi tiết nguyên vật liệu tiêu hao (Details)
IF OBJECT_ID(N'dbo.manufacturing_order_details', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.manufacturing_order_details
    (
        detail_id            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_mfg_order_details PRIMARY KEY,
        order_id             INT NOT NULL,
        component_product_id INT NOT NULL,
        component_variant_id INT NULL,
        component_unit_id    INT NULL,
        unit_conversion_to_base DECIMAL(18, 6) NOT NULL CONSTRAINT DF_mfg_detail_conv DEFAULT (1),
        planned_quantity     DECIMAL(18, 3) NOT NULL,
        actual_quantity      DECIMAL(18, 3) NOT NULL,
        base_quantity        DECIMAL(18, 3) NOT NULL CONSTRAINT DF_mfg_detail_base_qty DEFAULT (0),
        component_cost_price DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_details_cost DEFAULT (0),
        total_cost           DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_details_total DEFAULT (0),
        note                 NVARCHAR(255) NULL,
        CONSTRAINT FK_mfg_details_order FOREIGN KEY (order_id) REFERENCES dbo.manufacturing_orders(order_id) ON DELETE CASCADE,
        CONSTRAINT FK_mfg_details_component FOREIGN KEY (component_product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_mfg_details_unit FOREIGN KEY (component_unit_id) REFERENCES dbo.Units(unit_id)
    );

    CREATE NONCLUSTERED INDEX IX_mfg_details_order ON dbo.manufacturing_order_details(order_id);
    CREATE NONCLUSTERED INDEX IX_mfg_details_component ON dbo.manufacturing_order_details(component_product_id);
END
ELSE
BEGIN
    IF COL_LENGTH(N'dbo.manufacturing_order_details', N'component_unit_id') IS NULL
        ALTER TABLE dbo.manufacturing_order_details ADD component_unit_id INT NULL;

    IF COL_LENGTH(N'dbo.manufacturing_order_details', N'unit_conversion_to_base') IS NULL
        ALTER TABLE dbo.manufacturing_order_details ADD unit_conversion_to_base DECIMAL(18, 6) NOT NULL CONSTRAINT DF_mfg_detail_conv DEFAULT (1);

    IF COL_LENGTH(N'dbo.manufacturing_order_details', N'base_quantity') IS NULL
    BEGIN
        ALTER TABLE dbo.manufacturing_order_details ADD base_quantity DECIMAL(18, 3) NOT NULL CONSTRAINT DF_mfg_detail_base_qty DEFAULT (0);
        EXEC(N'UPDATE dbo.manufacturing_order_details SET base_quantity = actual_quantity * ISNULL(NULLIF(unit_conversion_to_base, 0), 1) WHERE base_quantity = 0 AND actual_quantity <> 0;');
    END;
END;
GO

-- 4. Bảng lưu vết biến động thẻ kho sản xuất (Movement Ledger)
IF OBJECT_ID(N'dbo.manufacturing_stock_movements', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.manufacturing_stock_movements
    (
        movement_id          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_mfg_stock_movements PRIMARY KEY,
        order_id             INT NOT NULL,
        product_id           INT NOT NULL,
        variant_id           INT NULL,
        movement_type        NVARCHAR(30) NOT NULL, -- MANUFACTURING_IN, MANUFACTURING_OUT, MANUFACTURING_CANCEL_OUT, MANUFACTURING_CANCEL_IN
        quantity_change      DECIMAL(18, 3) NOT NULL,
        unit_cost            DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_mov_unit_cost DEFAULT (0),
        total_amount         DECIMAL(18, 2) NOT NULL CONSTRAINT DF_mfg_mov_total_amount DEFAULT (0),
        movement_date        DATETIME NOT NULL,
        created_by           INT NOT NULL,
        created_at           DATETIME NOT NULL CONSTRAINT DF_mfg_mov_created DEFAULT (GETDATE()),
        note                 NVARCHAR(500) NULL,
        CONSTRAINT FK_mfg_movements_order FOREIGN KEY (order_id) REFERENCES dbo.manufacturing_orders(order_id)
    );

    CREATE NONCLUSTERED INDEX IX_mfg_mov_date ON dbo.manufacturing_stock_movements(movement_date);
    CREATE NONCLUSTERED INDEX IX_mfg_mov_product ON dbo.manufacturing_stock_movements(product_id, variant_id);
END;
GO

-- 5. Cập nhật Stored Procedure dbo.Report_GetInventoryMovement
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
            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'         AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SupplierReturnOutValue,
            SUM(CASE WHEN movement_type = N'SALES_OUT'           AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue,
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_IN', N'MANUFACTURING_CANCEL_IN') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS ManufacturingInValue,
            SUM(CASE WHEN movement_type IN (N'MANUFACTURING_OUT', N'MANUFACTURING_CANCEL_OUT') AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS ManufacturingOutValue
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
        CAST(ISNULL(ps.ManufacturingInQty, 0) AS DECIMAL(18, 3)) AS ManufacturingInQty,
        CAST(ISNULL(ps.ManufacturingOutQty, 0) AS DECIMAL(18, 3)) AS ManufacturingOutQty,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) AS DECIMAL(18, 3)) AS ClosingStock,
        CAST(ISNULL(p.stock, 0) AS DECIMAL(18, 3)) AS CurrentStock,
        CAST(ISNULL(ps.PurchaseInValue, 0) AS DECIMAL(18, 0)) AS PurchaseInValue,
        CAST(ISNULL(ps.SupplierReturnOutValue, 0) AS DECIMAL(18, 0)) AS SupplierReturnOutValue,
        CAST(ISNULL(ps.SalesOutValue, 0) AS DECIMAL(18, 0)) AS SalesOutValue,
        CAST(ISNULL(ps.ManufacturingInValue, 0) AS DECIMAL(18, 0)) AS ManufacturingInValue,
        CAST(ISNULL(ps.ManufacturingOutValue, 0) AS DECIMAL(18, 0)) AS ManufacturingOutValue,
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

PRINT N'Đã hoàn thành cấu hình CSDL cho phân hệ Sản xuất và cập nhật Báo cáo Xuất Nhập Tồn.';
GO
