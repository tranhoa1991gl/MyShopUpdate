SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Apply after every LAN workstation has been upgraded to the application version
-- that preserves the inactive-variant invariant in every stock movement.
BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.product_serials', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'serial_id') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'serial_number') IS NULL
       OR COL_LENGTH(N'dbo.product_serials', N'status') IS NULL
        THROW 51291, N'Thiếu cấu trúc trạng thái Serial/IMEI.', 1;

    IF OBJECT_ID(N'dbo.product_variants', N'U') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'variant_id') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'product_id') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'is_active') IS NULL
       OR COL_LENGTH(N'dbo.product_variants', N'stock_base_qty') IS NULL
        THROW 51292, N'Thiếu cấu trúc tồn kho biến thể.', 1;

    -- Preserve the exact legacy allocations before reclassifying them as
    -- unallocated product stock. dbo.products.stock is intentionally untouched.
    IF OBJECT_ID(N'dbo.product_variant_stock_reclassification_audit', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.product_variant_stock_reclassification_audit
        (
            audit_id BIGINT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_product_variant_stock_reclassification_audit PRIMARY KEY,
            migration_id NVARCHAR(150) NOT NULL,
            variant_id INT NOT NULL,
            product_id INT NOT NULL,
            color_value NVARCHAR(100) NULL,
            size_value NVARCHAR(100) NULL,
            previous_stock_base_qty DECIMAL(18,3) NOT NULL,
            reclassified_at DATETIME2(0) NOT NULL
                CONSTRAINT DF_product_variant_stock_reclassification_audit_at DEFAULT (SYSDATETIME())
        );
    END;

    IF COL_LENGTH(N'dbo.product_variant_stock_reclassification_audit', N'migration_id') IS NULL
       OR COL_LENGTH(N'dbo.product_variant_stock_reclassification_audit', N'variant_id') IS NULL
       OR COL_LENGTH(N'dbo.product_variant_stock_reclassification_audit', N'previous_stock_base_qty') IS NULL
        THROW 51293, N'Bảng lưu dấu vết dọn tồn biến thể không đúng cấu trúc.', 1;

    INSERT INTO dbo.product_variant_stock_reclassification_audit
    (
        migration_id, variant_id, product_id, color_value, size_value,
        previous_stock_base_qty, reclassified_at
    )
    SELECT
        N'20260905_serial_scrap_variant_cleanup',
        variant_id,
        product_id,
        color_value,
        size_value,
        stock_base_qty,
        SYSDATETIME()
    FROM dbo.product_variants WITH (UPDLOCK, HOLDLOCK)
    WHERE is_active = 0
      AND ISNULL(stock_base_qty, 0) <> 0;

    UPDATE dbo.product_variants
    SET stock_base_qty = 0,
        updated_at = GETDATE()
    WHERE is_active = 0
      AND ISNULL(stock_base_qty, 0) <> 0;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.product_variants
        WHERE is_active = 0
          AND ISNULL(stock_base_qty, 0) <> 0
    )
        THROW 51294, N'Không thể dọn hết tồn đang nằm trên biến thể đã ẩn.', 1;

    IF OBJECT_ID(N'dbo.CK_product_variants_inactive_stock_zero', N'C') IS NULL
    BEGIN
        ALTER TABLE dbo.product_variants WITH CHECK
        ADD CONSTRAINT CK_product_variants_inactive_stock_zero
            CHECK (is_active = 1 OR ISNULL(stock_base_qty, 0) = 0);
    END
    ELSE
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM sys.check_constraints
            WHERE object_id = OBJECT_ID(N'dbo.CK_product_variants_inactive_stock_zero', N'C')
              AND parent_object_id = OBJECT_ID(N'dbo.product_variants')
              AND definition LIKE N'%is_active%'
              AND definition LIKE N'%stock_base_qty%'
        )
            THROW 51295, N'Constraint CK_product_variants_inactive_stock_zero đang có định nghĩa không phù hợp.', 1;

        ALTER TABLE dbo.product_variants WITH CHECK
            CHECK CONSTRAINT CK_product_variants_inactive_stock_zero;
    END;

    -- Correct legacy scrap rows only when the inventory audit identifies the
    -- exact serial and product. Status 2 without that evidence remains repair.
    IF OBJECT_ID(N'dbo.product_serial_status_correction_audit', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.product_serial_status_correction_audit
        (
            audit_id BIGINT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_product_serial_status_correction_audit PRIMARY KEY,
            migration_id NVARCHAR(150) NOT NULL,
            serial_id INT NOT NULL,
            serial_number NVARCHAR(100) NULL,
            previous_status INT NOT NULL,
            corrected_status INT NOT NULL,
            inventory_check_id INT NULL,
            corrected_at DATETIME2(0) NOT NULL
                CONSTRAINT DF_product_serial_status_correction_audit_at DEFAULT (SYSDATETIME())
        );
    END;

    IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.product_serial_status_correction_audit
        (
            migration_id, serial_id, serial_number, previous_status,
            corrected_status, inventory_check_id, corrected_at
        )
        SELECT
            N'20260905_serial_scrap_variant_cleanup',
            ps.serial_id,
            ps.serial_number,
            2,
            4,
            evidence.check_id,
            SYSDATETIME()
        FROM dbo.product_serials ps WITH (UPDLOCK, HOLDLOCK)
        CROSS APPLY
        (
            SELECT TOP (1) ic.check_id
            FROM dbo.inventory_checks ic
            INNER JOIN dbo.inventory_check_details d
                ON d.check_id = ic.check_id
               AND d.product_id = ps.product_id
            WHERE CONVERT(NVARCHAR(MAX), ic.note) =
                N'Xuất hủy trực tiếp Serial: ' + LTRIM(RTRIM(ISNULL(ps.serial_number, N'')))
              AND d.difference = -1
            ORDER BY ic.check_id DESC
        ) evidence
        WHERE ps.status = 2
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.product_serial_status_correction_audit a
              WHERE a.migration_id = N'20260905_serial_scrap_variant_cleanup'
                AND a.serial_id = ps.serial_id
          );

        UPDATE ps
        SET ps.status = 4
        FROM dbo.product_serials ps
        INNER JOIN dbo.product_serial_status_correction_audit a
            ON a.serial_id = ps.serial_id
           AND a.migration_id = N'20260905_serial_scrap_variant_cleanup'
           AND a.previous_status = 2
           AND a.corrected_status = 4
        WHERE ps.status = 2;
    END;

    IF OBJECT_ID(N'dbo.ProductSerials_Scrap', N'P') IS NULL
        THROW 51297, N'Thiếu procedure dbo.ProductSerials_Scrap.', 1;

    EXEC(N'ALTER PROCEDURE dbo.ProductSerials_Scrap
        @SerialNumber NVARCHAR(100),
        @EmployeeId INT,
        @Reason NVARCHAR(255)
    AS
    BEGIN
        SET NOCOUNT ON;
        SET XACT_ABORT ON;

        SET @SerialNumber = NULLIF(LTRIM(RTRIM(@SerialNumber)), N'''');
        IF @SerialNumber IS NULL
            THROW 51160, N''Serial/IMEI không hợp lệ.'', 1;

        BEGIN TRY
            BEGIN TRANSACTION;

            DECLARE @SerialId INT, @ProductId INT, @CurrentStock DECIMAL(18,3);
            SELECT TOP (1) @SerialId = serial_id, @ProductId = product_id
            FROM dbo.product_serials WITH (UPDLOCK, HOLDLOCK)
            WHERE LTRIM(RTRIM(ISNULL(serial_number, N''''))) = @SerialNumber
              AND status = 0
            ORDER BY serial_id;

            IF @SerialId IS NULL
                THROW 51164, N''Serial/IMEI không tồn tại hoặc không còn trong kho.'', 1;

            SELECT @CurrentStock = ISNULL(stock, 0)
            FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
            WHERE product_id = @ProductId;

            IF @CurrentStock IS NULL OR @CurrentStock < 1
                THROW 51165, N''Tồn kho không đủ để xuất hủy Serial/IMEI.'', 1;

            UPDATE dbo.product_serials
            SET status = 4
            WHERE serial_id = @SerialId AND status = 0;

            IF @@ROWCOUNT <> 1
                THROW 51166, N''Không thể cập nhật Serial/IMEI xuất hủy.'', 1;

            UPDATE dbo.products
            SET stock = ISNULL(stock, 0) - 1
            WHERE product_id = @ProductId;

            DECLARE @CheckCode VARCHAR(20), @Attempt INT = 0;
            WHILE @Attempt < 10
            BEGIN
                SET @CheckCode = ''XH'' + CONVERT(CHAR(8), GETDATE(), 112)
                    + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), '':'', '''')
                    + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), ''-'', ''''), 4);
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.inventory_checks WITH (UPDLOCK, HOLDLOCK)
                    WHERE check_code = @CheckCode
                )
                    BREAK;
                SET @Attempt = @Attempt + 1;
            END;

            IF @Attempt >= 10
                THROW 51167, N''Không thể tạo mã phiếu xuất hủy duy nhất.'', 1;

            INSERT INTO dbo.inventory_checks(check_code, check_date, employee_id, note)
            VALUES(@CheckCode, GETDATE(), @EmployeeId, N''Xuất hủy trực tiếp Serial: '' + @SerialNumber);

            DECLARE @CheckId INT = CONVERT(INT, SCOPE_IDENTITY());
            INSERT INTO dbo.inventory_check_details
                (check_id, product_id, system_stock, actual_stock, difference, reason)
            VALUES(@CheckId, @ProductId, @CurrentStock, @CurrentStock - 1, -1, @Reason);

            COMMIT TRANSACTION;
            SELECT 1 AS Result;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;
    END;');

    IF OBJECT_ID(N'dbo.Products_GetSerialTraceability', N'P') IS NOT NULL
    BEGIN
        EXEC(N'ALTER PROCEDURE dbo.Products_GetSerialTraceability
            @ProductId INT
        AS
        BEGIN
            SET NOCOUNT ON;

            SELECT
                ps.serial_id,
                ps.import_id,
                ps.order_id,
                ISNULL(ps.serial_number, N''Chưa cập nhật'') AS [Mã Serial / IMEI],
                i.import_code AS [Mã phiếu nhập],
                CONVERT(VARCHAR(10), i.import_date, 103) AS [Ngày nhập],
                ISNULL(sup.supplier_name, N''Không xác định'') AS [Nhà cung cấp],
                ps.sell_price_override AS [Giá bán riêng],
                ISNULL(ps.product_color, N'''') AS [Màu],
                ISNULL(ps.note, N'''') AS [Ghi chú],
                CASE
                    WHEN ps.status = 0 THEN N''🟢 Trong kho''
                    WHEN ps.status = 1 THEN N''🔴 Đã bán''
                    WHEN ps.status = 2 THEN N''🟡 Đang sửa chữa''
                    WHEN ps.status = 3 THEN N''🟠 Đã trả NCC''
                    WHEN ps.status = 4 THEN N''⚫ Đã xuất hủy''
                    ELSE N''Không xác định''
                END AS [Trạng thái],
                ISNULL(o.order_code, N'''') AS [Mã đơn bán],
                CASE
                    WHEN o.order_date IS NOT NULL THEN CONVERT(VARCHAR(10), o.order_date, 103)
                    ELSE N''''
                END AS [Ngày bán]
            FROM dbo.product_serials ps
            INNER JOIN dbo.imports i ON ps.import_id = i.import_id
            LEFT JOIN dbo.suppliers sup ON i.supplier_id = sup.supplier_id
            LEFT JOIN dbo.orders o ON ps.order_id = o.order_id
            WHERE ps.product_id = @ProductId
            ORDER BY ps.serial_id DESC;
        END;');
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
