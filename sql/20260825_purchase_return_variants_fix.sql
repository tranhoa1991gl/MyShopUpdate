SET NOCOUNT ON;
SET XACT_ABORT ON;

/*
    Bản vá đối soát mới, không chỉnh sửa migration đã phát hành ngày 20/08/2026.
    Mục đích:
    - Đảm bảo chi tiết trả nhà cung cấp có liên kết biến thể hợp lệ.
    - Khôi phục khóa ngoại/chỉ mục nếu CSDL cũ còn thiếu.
    - Áp lại bốn thủ tục phiên bản nhiều đơn vị tính hiện hành.
    - Không thực hiện lại phép điều chỉnh tồn kho lịch sử.
*/

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NULL
        THROW 51200, N'Không tìm thấy bảng purchase_return_details.', 1;

    IF OBJECT_ID(N'dbo.product_variants', N'U') IS NULL
        THROW 51201, N'Không tìm thấy bảng product_variants.', 1;

    IF OBJECT_ID(N'dbo.import_details', N'U') IS NULL
        THROW 51202, N'Không tìm thấy bảng import_details.', 1;

    IF COL_LENGTH(N'dbo.purchase_return_details', N'variant_id') IS NULL
        ALTER TABLE dbo.purchase_return_details ADD variant_id INT NULL;

    UPDATE prd
    SET prd.variant_id = id.variant_id
    FROM dbo.purchase_return_details prd
    INNER JOIN dbo.import_details id ON id.import_detail_id = prd.import_detail_id
    WHERE prd.variant_id IS NULL
      AND id.variant_id IS NOT NULL;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.purchase_return_details prd
        LEFT JOIN dbo.product_variants pv ON pv.variant_id = prd.variant_id
        WHERE prd.variant_id IS NOT NULL
          AND pv.variant_id IS NULL
    )
        THROW 51203, N'Không thể xác thực biến thể trả NCC vì còn dữ liệu mồ côi.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'dbo.purchase_return_details')
          AND name = N'FK_purchase_return_details_product_variants'
    )
    BEGIN
        ALTER TABLE dbo.purchase_return_details WITH CHECK
        ADD CONSTRAINT FK_purchase_return_details_product_variants
            FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);
    END
    ELSE
    BEGIN
        ALTER TABLE dbo.purchase_return_details
            WITH CHECK CHECK CONSTRAINT FK_purchase_return_details_product_variants;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.purchase_return_details')
          AND name = N'IX_purchase_return_details_variant_id'
    )
    BEGIN
        CREATE INDEX IX_purchase_return_details_variant_id
            ON dbo.purchase_return_details(variant_id);
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
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
