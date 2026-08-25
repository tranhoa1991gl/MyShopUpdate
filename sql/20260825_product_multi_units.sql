SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_unit_conversions
    (
        conversion_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_unit_conversions PRIMARY KEY,
        product_id INT NOT NULL,
        product_variant_id INT NULL,
        unit_id INT NOT NULL,
        conversion_to_base DECIMAL(18,6) NOT NULL,
        is_base BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_base DEFAULT(0),
        is_purchase_unit BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_purchase DEFAULT(1),
        is_sale_unit BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_sale DEFAULT(1),
        barcode NVARCHAR(100) NULL,
        sell_price DECIMAL(18,2) NULL,
        import_price DECIMAL(18,2) NULL,
        sort_order INT NOT NULL CONSTRAINT DF_product_unit_conversions_sort DEFAULT(0),
        is_active BIT NOT NULL CONSTRAINT DF_product_unit_conversions_active DEFAULT(1),
        created_at DATETIME NOT NULL CONSTRAINT DF_product_unit_conversions_created DEFAULT(GETDATE()),
        updated_at DATETIME NULL,
        CONSTRAINT FK_product_unit_conversions_products FOREIGN KEY(product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_product_unit_conversions_units FOREIGN KEY(unit_id) REFERENCES dbo.Units(unit_id),
        CONSTRAINT CK_product_unit_conversions_ratio CHECK(conversion_to_base > 0)
    );
END;

IF COL_LENGTH(N'dbo.order_items', N'unit_id') IS NULL
    ALTER TABLE dbo.order_items ADD unit_id INT NULL;
IF COL_LENGTH(N'dbo.order_items', N'input_quantity') IS NULL
    ALTER TABLE dbo.order_items ADD input_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.order_items', N'base_quantity') IS NULL
    ALTER TABLE dbo.order_items ADD base_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.order_items', N'unit_conversion_to_base') IS NULL
    ALTER TABLE dbo.order_items ADD unit_conversion_to_base DECIMAL(18,6) NULL;
IF COL_LENGTH(N'dbo.order_items', N'unit_name_snapshot') IS NULL
    ALTER TABLE dbo.order_items ADD unit_name_snapshot NVARCHAR(50) NULL;
IF COL_LENGTH(N'dbo.order_items', N'original_order_item_id') IS NULL
    ALTER TABLE dbo.order_items ADD original_order_item_id INT NULL;

IF COL_LENGTH(N'dbo.import_details', N'unit_id') IS NULL
    ALTER TABLE dbo.import_details ADD unit_id INT NULL;
IF COL_LENGTH(N'dbo.import_details', N'input_quantity') IS NULL
    ALTER TABLE dbo.import_details ADD input_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.import_details', N'base_quantity') IS NULL
    ALTER TABLE dbo.import_details ADD base_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.import_details', N'unit_conversion_to_base') IS NULL
    ALTER TABLE dbo.import_details ADD unit_conversion_to_base DECIMAL(18,6) NULL;

UPDATE oi
SET unit_id = ISNULL(oi.unit_id, p.unit_id),
    input_quantity = ISNULL(oi.input_quantity, oi.quantity),
    base_quantity = ISNULL(oi.base_quantity,
        CASE WHEN oi.quantity < 0
             THEN oi.quantity - ISNULL(oi.gift_quantity, 0)
             ELSE oi.quantity + ISNULL(oi.gift_quantity, 0) END),
    unit_conversion_to_base = ISNULL(oi.unit_conversion_to_base, 1)
FROM dbo.order_items oi
INNER JOIN dbo.products p ON p.product_id = oi.product_id
WHERE oi.unit_id IS NULL OR oi.input_quantity IS NULL
   OR oi.base_quantity IS NULL OR oi.unit_conversion_to_base IS NULL;

UPDATE id
SET unit_id = ISNULL(id.unit_id, p.unit_id),
    input_quantity = ISNULL(id.input_quantity, id.quantity),
    base_quantity = ISNULL(id.base_quantity, id.quantity),
    unit_conversion_to_base = ISNULL(id.unit_conversion_to_base, 1)
FROM dbo.import_details id
INNER JOIN dbo.products p ON p.product_id = id.product_id
WHERE id.unit_id IS NULL OR id.input_quantity IS NULL
   OR id.base_quantity IS NULL OR id.unit_conversion_to_base IS NULL;

INSERT INTO dbo.product_unit_conversions
(
    product_id, product_variant_id, unit_id, conversion_to_base, is_base,
    is_purchase_unit, is_sale_unit, barcode, sell_price, import_price,
    sort_order, is_active, created_at
)
SELECT
    p.product_id, NULL, p.unit_id, 1, 1,
    1, 1, NULL, p.sell_price, p.import_price,
    0, 1, GETDATE()
FROM dbo.products p
WHERE p.unit_id IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.product_unit_conversions c
      WHERE c.product_id = p.product_id
        AND c.product_variant_id IS NULL
        AND c.unit_id = p.unit_id
        AND c.is_base = 1
  );

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.product_unit_conversions')
      AND name = N'IX_product_unit_conversions_product'
)
    CREATE INDEX IX_product_unit_conversions_product
        ON dbo.product_unit_conversions(product_id, product_variant_id, is_active, sort_order);

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.PurchaseReturns_GetImportDetailsForReturn
    @ImportId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        id.import_detail_id AS ImportDetailId,
        id.import_id AS ImportId,
        id.product_id AS ProductId,
        id.variant_id AS VariantId,
        CASE WHEN pv.variant_id IS NULL THEN p.product_code ELSE pv.sku_code END AS ProductCode,
        ISNULL(CASE WHEN pv.variant_id IS NULL THEN p.barcode ELSE NULLIF(pv.barcode, N'') END, N'') AS Barcode,
        CASE
            WHEN pv.variant_id IS NULL THEN p.product_name
            ELSE p.product_name + N' • ' + COALESCE(NULLIF(pv.variant_name, N''),
                NULLIF(CONCAT(NULLIF(pv.color_value, N''),
                    CASE WHEN NULLIF(pv.color_value, N'') IS NOT NULL AND NULLIF(pv.size_value, N'') IS NOT NULL THEN N' / ' ELSE N'' END,
                    NULLIF(pv.size_value, N'')), N''), pv.sku_code)
        END AS ProductName,
        COALESCE(NULLIF(u.unit_name, N''), NULLIF(baseUnit.unit_name, N''), N'') AS UnitName,
        ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1) AS UnitConversionToBase,
        ISNULL(id.quantity, 0) AS ImportedQty,
        ISNULL(r.ReturnedQty, 0) AS ReturnedQty,
        ISNULL(id.quantity, 0) - ISNULL(r.ReturnedQty, 0) AS MaxReturnQty,
        CAST(0 AS INT) AS ReturnQty,
        ISNULL(id.import_price, 0) AS ImportPrice,
        CAST(0 AS DECIMAL(18,0)) AS ReturnAmount,
        CAST(N'' AS NVARCHAR(255)) AS Reason
    FROM dbo.import_details id
    INNER JOIN dbo.products p ON p.product_id = id.product_id
    LEFT JOIN dbo.product_variants pv ON pv.variant_id = id.variant_id
    LEFT JOIN dbo.Units u ON u.unit_id = id.unit_id
    LEFT JOIN dbo.Units baseUnit ON baseUnit.unit_id = p.unit_id
    OUTER APPLY
    (
        SELECT ISNULL(SUM(prd.quantity), 0) AS ReturnedQty
        FROM dbo.purchase_return_details prd
        INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
        WHERE prd.import_detail_id = id.import_detail_id
          AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ) r
    WHERE id.import_id = @ImportId
      AND ISNULL(id.quantity, 0) > ISNULL(r.ReturnedQty, 0)
    ORDER BY id.import_detail_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.PurchaseReturns_Insert
    @ReturnCode VARCHAR(30),
    @ImportId INT,
    @SupplierId INT,
    @EmployeeId INT,
    @TotalAmount DECIMAL(18,0),
    @Note NVARCHAR(MAX),
    @DetailsXml NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExistingReturnId INT;
    SELECT TOP 1 @ExistingReturnId = return_id
    FROM dbo.purchase_returns
    WHERE return_code = @ReturnCode;

    IF @ExistingReturnId IS NOT NULL
    BEGIN
        SELECT @ExistingReturnId AS ReturnId;
        RETURN;
    END;

    DECLARE @xml XML = TRY_CAST(@DetailsXml AS XML);
    IF @xml IS NULL
        THROW 51000, N'Dữ liệu chi tiết trả hàng không hợp lệ.', 1;

    DECLARE @Detail TABLE
    (
        ImportDetailId INT NOT NULL,
        ProductId INT NOT NULL,
        RequestedVariantId INT NULL,
        Quantity INT NOT NULL,
        ImportPrice DECIMAL(18,0) NOT NULL,
        Reason NVARCHAR(255) NULL
    );

    INSERT INTO @Detail(ImportDetailId, ProductId, RequestedVariantId, Quantity, ImportPrice, Reason)
    SELECT
        X.Item.value('@ImportDetailId', 'INT'),
        X.Item.value('@ProductId', 'INT'),
        TRY_CONVERT(INT, NULLIF(X.Item.value('@VariantId', 'NVARCHAR(20)'), N'')),
        X.Item.value('@Quantity', 'INT'),
        X.Item.value('@ImportPrice', 'DECIMAL(18,0)'),
        X.Item.value('@Reason', 'NVARCHAR(255)')
    FROM @xml.nodes('/Details/Item') AS X(Item);

    IF NOT EXISTS (SELECT 1 FROM @Detail)
        THROW 51001, N'Chưa có hàng trả nhà cung cấp.', 1;
    IF EXISTS (SELECT 1 FROM @Detail WHERE Quantity <= 0)
        THROW 51002, N'Số lượng trả phải lớn hơn 0.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.imports i
        WHERE i.import_id = @ImportId
          AND i.supplier_id = @SupplierId
          AND ISNULL(i.status, N'') IN (N'Completed', N'Paid')
    )
        THROW 51003, N'Phiếu nhập không hợp lệ hoặc chưa nhập kho.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM @Detail d
        LEFT JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        WHERE id.import_detail_id IS NULL
           OR id.import_id <> @ImportId
           OR id.product_id <> d.ProductId
           OR (d.RequestedVariantId IS NOT NULL AND ISNULL(id.variant_id, 0) <> d.RequestedVariantId)
    )
        THROW 51004, N'Hàng hoặc biến thể trả không thuộc phiếu nhập đã chọn.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM @Detail d
        INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        OUTER APPLY
        (
            SELECT ISNULL(SUM(prd.quantity), 0) AS ReturnedQty
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE d.Quantity > ISNULL(id.quantity, 0) - ISNULL(r.ReturnedQty, 0)
    )
        THROW 51005, N'Số lượng trả vượt quá số lượng còn có thể trả của phiếu nhập.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.products p
        INNER JOIN
        (
            SELECT d.ProductId,
                   SUM(d.Quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM @Detail d
            INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
            GROUP BY d.ProductId
        ) d ON d.ProductId = p.product_id
        WHERE ISNULL(p.stock, 0) < d.ReturnQty
    )
        THROW 51006, N'Tồn kho hiện tại không đủ để trả nhà cung cấp. Vui lòng kiểm tra lại kho.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM
        (
            SELECT id.variant_id,
                   SUM(d.Quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM @Detail d
            INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
            WHERE id.variant_id IS NOT NULL
            GROUP BY id.variant_id
        ) d
        INNER JOIN dbo.product_variants pv ON pv.variant_id = d.variant_id
        WHERE ISNULL(pv.stock_base_qty, 0) < d.ReturnQty
    )
        THROW 51007, N'Tồn của một hoặc nhiều biến thể không đủ để trả nhà cung cấp.', 1;

    DECLARE @CalcTotal DECIMAL(18,0);
    SELECT @CalcTotal = ISNULL(SUM(Quantity * ImportPrice), 0) FROM @Detail;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.purchase_returns
        (
            return_code, import_id, supplier_id, employee_id,
            return_date, total_amount, note, status
        )
        VALUES
        (
            @ReturnCode, @ImportId, @SupplierId, @EmployeeId,
            GETDATE(), @CalcTotal, @Note, N'Completed'
        );

        DECLARE @ReturnId INT = CONVERT(INT, SCOPE_IDENTITY());

        IF @ReturnId <= 0
        BEGIN
            DELETE FROM dbo.purchase_returns WHERE return_id = @ReturnId;

            INSERT INTO dbo.purchase_returns
            (
                return_code, import_id, supplier_id, employee_id,
                return_date, total_amount, note, status
            )
            VALUES
            (
                @ReturnCode, @ImportId, @SupplierId, @EmployeeId,
                GETDATE(), @CalcTotal, @Note, N'Completed'
            );

            SET @ReturnId = CONVERT(INT, SCOPE_IDENTITY());
        END;

        IF @ReturnId <= 0
            THROW 51008, N'Không thể tạo mã phiếu trả hàng hợp lệ.', 1;

        INSERT INTO dbo.purchase_return_details
        (
            return_id, import_detail_id, product_id, variant_id,
            quantity, import_price, total, reason
        )
        SELECT
            @ReturnId, d.ImportDetailId, d.ProductId, id.variant_id,
            d.Quantity, d.ImportPrice, d.Quantity * d.ImportPrice, d.Reason
        FROM @Detail d
        INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId;

        UPDATE p
        SET p.stock = ISNULL(p.stock, 0) - d.ReturnQty
        FROM dbo.products p
        INNER JOIN
        (
            SELECT d.ProductId,
                   SUM(d.Quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM @Detail d
            INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
            GROUP BY d.ProductId
        ) d ON d.ProductId = p.product_id;

        UPDATE pv
        SET pv.stock_base_qty = ISNULL(pv.stock_base_qty, 0) - d.ReturnQty,
            pv.updated_at = GETDATE()
        FROM dbo.product_variants pv
        INNER JOIN
        (
            SELECT id.variant_id,
                   SUM(d.Quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM @Detail d
            INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
            WHERE id.variant_id IS NOT NULL
            GROUP BY id.variant_id
        ) d ON d.variant_id = pv.variant_id;

        COMMIT TRANSACTION;
        SELECT @ReturnId AS ReturnId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() IN (2601, 2627)
        BEGIN
            SELECT TOP 1 @ExistingReturnId = return_id
            FROM dbo.purchase_returns WHERE return_code = @ReturnCode;
            IF @ExistingReturnId IS NOT NULL
            BEGIN
                SELECT @ExistingReturnId AS ReturnId;
                RETURN;
            END;
        END;

        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.PurchaseReturnHistory_GetReturnDetails
    @ReturnId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        prd.return_detail_id AS ReturnDetailId,
        prd.return_id AS ReturnId,
        prd.import_detail_id AS ImportDetailId,
        prd.product_id AS ProductId,
        prd.variant_id AS VariantId,
        ISNULL(CASE WHEN pv.variant_id IS NULL THEN p.product_code ELSE pv.sku_code END, N'') AS ProductCode,
        ISNULL(CASE WHEN pv.variant_id IS NULL THEN p.barcode ELSE NULLIF(pv.barcode, N'') END, N'') AS Barcode,
        CASE
            WHEN pv.variant_id IS NULL THEN ISNULL(p.product_name, N'')
            ELSE ISNULL(p.product_name, N'') + N' • ' + COALESCE(NULLIF(pv.variant_name, N''),
                NULLIF(CONCAT(NULLIF(pv.color_value, N''),
                    CASE WHEN NULLIF(pv.color_value, N'') IS NOT NULL AND NULLIF(pv.size_value, N'') IS NOT NULL THEN N' / ' ELSE N'' END,
                    NULLIF(pv.size_value, N'')), N''), pv.sku_code)
        END AS ProductName,
        COALESCE(NULLIF(u.unit_name, N''), NULLIF(baseUnit.unit_name, N''), N'') AS UnitName,
        ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1) AS UnitConversionToBase,
        ISNULL(prd.quantity, 0) AS Quantity,
        ISNULL(prd.import_price, 0) AS ImportPrice,
        ISNULL(prd.total, ISNULL(prd.import_price, 0) * ISNULL(prd.quantity, 0)) AS Total,
        ISNULL(prd.reason, N'') AS Reason
    FROM dbo.purchase_return_details prd
    LEFT JOIN dbo.products p ON p.product_id = prd.product_id
    LEFT JOIN dbo.product_variants pv ON pv.variant_id = prd.variant_id
    LEFT JOIN dbo.import_details id ON id.import_detail_id = prd.import_detail_id
    LEFT JOIN dbo.Units u ON u.unit_id = id.unit_id
    LEFT JOIN dbo.Units baseUnit ON baseUnit.unit_id = p.unit_id
    WHERE prd.return_id = @ReturnId
    ORDER BY prd.return_detail_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.PurchaseReturnHistory_CancelReturn
    @ReturnId INT,
    @EmployeeId INT,
    @Reason NVARCHAR(500) = N''
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = LTRIM(RTRIM(ISNULL(@Reason, N'')));
    IF @Reason = N'' SET @Reason = N'Hủy phiếu trả NCC';

    IF NOT EXISTS (SELECT 1 FROM dbo.purchase_returns WHERE return_id = @ReturnId)
        THROW 51020, N'Không tìm thấy phiếu trả NCC.', 1;

    IF EXISTS
    (
        SELECT 1 FROM dbo.purchase_returns
        WHERE return_id = @ReturnId
          AND ISNULL(status, N'') IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    )
        THROW 51021, N'Phiếu trả NCC này đã bị hủy trước đó.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE p
        SET p.stock = ISNULL(p.stock, 0) + d.ReturnQty
        FROM dbo.products p
        INNER JOIN
        (
            SELECT prd.product_id,
                   SUM(prd.quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM dbo.purchase_return_details prd
            LEFT JOIN dbo.import_details id ON id.import_detail_id = prd.import_detail_id
            WHERE prd.return_id = @ReturnId
            GROUP BY prd.product_id
        ) d ON d.product_id = p.product_id;

        UPDATE pv
        SET pv.stock_base_qty = ISNULL(pv.stock_base_qty, 0) + d.ReturnQty,
            pv.updated_at = GETDATE()
        FROM dbo.product_variants pv
        INNER JOIN
        (
            SELECT prd.variant_id,
                   SUM(prd.quantity * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)) AS ReturnQty
            FROM dbo.purchase_return_details prd
            LEFT JOIN dbo.import_details id ON id.import_detail_id = prd.import_detail_id
            WHERE prd.return_id = @ReturnId AND prd.variant_id IS NOT NULL
            GROUP BY prd.variant_id
        ) d ON d.variant_id = pv.variant_id;

        UPDATE dbo.purchase_returns
        SET status = N'Cancelled',
            note = ISNULL(note, N'') +
                   CASE WHEN ISNULL(note, N'') = N'' THEN N'' ELSE CHAR(13) + CHAR(10) END +
                   N'[ĐÃ HỦY ' + CONVERT(NVARCHAR(19), GETDATE(), 120) + N'] ' + @Reason
        WHERE return_id = @ReturnId;

        COMMIT TRANSACTION;
        SELECT 1 AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
