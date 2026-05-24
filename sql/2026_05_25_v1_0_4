/* =====================================================
   PATCH: Cho phép nhập hàng Serial/IMEI nhưng bỏ trống IMEI
   Mục tiêu:
   - Nhập số lượng 20 sản phẩm có Serial
   - Tạo 20 dòng trong product_serials
   - serial_number = NULL
   - Sau này cập nhật IMEI sau
===================================================== */

SET NOCOUNT ON;
GO

/* =====================================================
   BƯỚC 1: Xóa UNIQUE CONSTRAINT cũ trên serial_number nếu có
===================================================== */

DECLARE @ConstraintName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

WHILE EXISTS (
    SELECT 1
    FROM sys.key_constraints kc
    INNER JOIN sys.index_columns ic
        ON kc.parent_object_id = ic.object_id
       AND kc.unique_index_id = ic.index_id
    INNER JOIN sys.columns c
        ON ic.object_id = c.object_id
       AND ic.column_id = c.column_id
    WHERE kc.parent_object_id = OBJECT_ID(N'dbo.product_serials')
      AND kc.type = 'UQ'
      AND c.name = 'serial_number'
)
BEGIN
    SELECT TOP 1 @ConstraintName = kc.name
    FROM sys.key_constraints kc
    INNER JOIN sys.index_columns ic
        ON kc.parent_object_id = ic.object_id
       AND kc.unique_index_id = ic.index_id
    INNER JOIN sys.columns c
        ON ic.object_id = c.object_id
       AND ic.column_id = c.column_id
    WHERE kc.parent_object_id = OBJECT_ID(N'dbo.product_serials')
      AND kc.type = 'UQ'
      AND c.name = 'serial_number';

    SET @Sql = N'ALTER TABLE dbo.product_serials DROP CONSTRAINT ' + QUOTENAME(@ConstraintName);
    EXEC(@Sql);
END
GO

/* =====================================================
   BƯỚC 2: Xóa UNIQUE INDEX cũ trên serial_number nếu có
   Không xóa index mới UX_product_serials_serial_number_notnull nếu đã tồn tại
===================================================== */

DECLARE @IndexName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

WHILE EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic
        ON i.object_id = ic.object_id
       AND i.index_id = ic.index_id
    INNER JOIN sys.columns c
        ON ic.object_id = c.object_id
       AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(N'dbo.product_serials')
      AND i.is_unique = 1
      AND c.name = 'serial_number'
      AND i.name <> 'UX_product_serials_serial_number_notnull'
)
BEGIN
    SELECT TOP 1 @IndexName = i.name
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic
        ON i.object_id = ic.object_id
       AND i.index_id = ic.index_id
    INNER JOIN sys.columns c
        ON ic.object_id = c.object_id
       AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(N'dbo.product_serials')
      AND i.is_unique = 1
      AND c.name = 'serial_number'
      AND i.name <> 'UX_product_serials_serial_number_notnull';

    SET @Sql = N'DROP INDEX ' + QUOTENAME(@IndexName) + N' ON dbo.product_serials';
    EXEC(@Sql);
END
GO

/* =====================================================
   BƯỚC 3: Cho phép serial_number được NULL
===================================================== */

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.product_serials')
      AND name = 'serial_number'
      AND is_nullable = 0
)
BEGIN
    ALTER TABLE dbo.product_serials
    ALTER COLUMN serial_number NVARCHAR(100) NULL;
END
GO

/* =====================================================
   BƯỚC 4: Chuyển serial_number rỗng thành NULL
===================================================== */

UPDATE dbo.product_serials
SET serial_number = NULL
WHERE LTRIM(RTRIM(ISNULL(serial_number, N''))) = N'';
GO

/* =====================================================
   BƯỚC 5: Tạo UNIQUE INDEX mới
   Chỉ chặn trùng khi serial_number có giá trị.
   Nhiều dòng NULL vẫn được phép.
===================================================== */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_product_serials_serial_number_notnull'
      AND object_id = OBJECT_ID(N'dbo.product_serials')
)
BEGIN
    CREATE UNIQUE INDEX UX_product_serials_serial_number_notnull
    ON dbo.product_serials(serial_number)
    WHERE serial_number IS NOT NULL;
END
GO

/* =====================================================
   BƯỚC 6: Tạo lại proc ProductSerials_Insert
   Cho phép @serial_number NULL hoặc rỗng
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_Insert', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_Insert;
GO

CREATE PROC dbo.ProductSerials_Insert
    @product_id INT,
    @import_id INT,
    @serial_number NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.product_serials
    (
        product_id,
        import_id,
        serial_number,
        status,
        created_at
    )
    VALUES
    (
        @product_id,
        @import_id,
        NULLIF(LTRIM(RTRIM(@serial_number)), N''),
        0,
        GETDATE()
    );
END
GO

/* =====================================================
   BƯỚC 7: Tạo lại proc lấy serial còn trong kho để bán
   Chỉ lấy serial đã có IMEI.
   Không lấy dòng serial_number NULL.
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_GetAvailable', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_GetAvailable;
GO

CREATE PROC dbo.ProductSerials_GetAvailable
    @product_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM dbo.product_serials
    WHERE product_id = @product_id
      AND status = 0
      AND serial_number IS NOT NULL
    ORDER BY serial_id DESC;
END
GO

/* =====================================================
   BƯỚC 8: Tạo lại proc truy xuất serial
   Dòng chưa có IMEI sẽ hiển thị "Chưa cập nhật".
===================================================== */

IF OBJECT_ID(N'dbo.Products_GetSerialTraceability', N'P') IS NOT NULL
    DROP PROC dbo.Products_GetSerialTraceability;
GO

CREATE PROC dbo.Products_GetSerialTraceability
    @ProductId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ps.serial_id,
        ps.import_id,
        ps.order_id,

        ISNULL(ps.serial_number, N'Chưa cập nhật') AS [Mã Serial / IMEI],

        i.import_code AS [Mã phiếu nhập],
        CONVERT(VARCHAR(10), i.import_date, 103) AS [Ngày nhập],

        ISNULL(sup.supplier_name, N'Không xác định') AS [Nhà cung cấp],

        CASE 
            WHEN ps.status = 0 THEN N'🟢 Trong kho'
            ELSE N'🔴 Đã bán'
        END AS [Trạng thái],

        ISNULL(o.order_code, N'') AS [Mã đơn bán],

        CASE 
            WHEN o.order_date IS NOT NULL THEN CONVERT(VARCHAR(10), o.order_date, 103)
            ELSE N''
        END AS [Ngày bán]

    FROM dbo.product_serials ps
    INNER JOIN dbo.imports i 
        ON ps.import_id = i.import_id
    LEFT JOIN dbo.suppliers sup 
        ON i.supplier_id = sup.supplier_id
    LEFT JOIN dbo.orders o 
        ON ps.order_id = o.order_id
    WHERE ps.product_id = @ProductId
    ORDER BY ps.serial_id DESC;
END
GO

/* =====================================================
   BƯỚC 9: Proc cập nhật IMEI sau này
   Dùng cho dòng serial_number đang NULL.
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_UpdateBlankSerial', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_UpdateBlankSerial;
GO

CREATE PROC dbo.ProductSerials_UpdateBlankSerial
    @serial_id INT,
    @serial_number NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');

    IF @serial_number IS NULL
    BEGIN
        RAISERROR(N'Vui lòng nhập Serial/IMEI.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
    )
    BEGIN
        RAISERROR(N'Không tìm thấy dòng Serial/IMEI cần cập nhật.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_number = @serial_number
          AND serial_id <> @serial_id
    )
    BEGIN
        RAISERROR(N'Serial/IMEI này đã tồn tại trong hệ thống.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
          AND status <> 0
    )
    BEGIN
        RAISERROR(N'Không thể cập nhật IMEI cho sản phẩm đã bán.', 16, 1);
        RETURN;
    END

    UPDATE dbo.product_serials
    SET serial_number = @serial_number
    WHERE serial_id = @serial_id
      AND status = 0;
END
GO

/* =====================================================
   BƯỚC 10: Kiểm tra nhanh
===================================================== */

SELECT 
    COLUMN_NAME,
    IS_NULLABLE,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'product_serials'
  AND COLUMN_NAME = 'serial_number';
GO

SELECT 
    name,
    is_unique,
    has_filter,
    filter_definition
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.product_serials')
  AND name = 'UX_product_serials_serial_number_notnull';
GO




/* =====================================================
   PATCH: Thêm giá bán riêng và ghi chú cho từng Serial/IMEI
   Mục tiêu:
   - Mỗi IMEI có thể có giá bán riêng
   - Mỗi IMEI có ghi chú ngoại hình / pin / màu / tình trạng
   - Nếu không có giá riêng thì dùng giá bán mặc định của sản phẩm
===================================================== */

SET NOCOUNT ON;
GO

/* =====================================================
   BƯỚC 1: Thêm cột sell_price_override nếu chưa có
===================================================== */

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.product_serials')
      AND name = 'sell_price_override'
)
BEGIN
    ALTER TABLE dbo.product_serials
    ADD sell_price_override DECIMAL(18, 0) NULL;
END
GO

/* =====================================================
   BƯỚC 2: Thêm cột note nếu chưa có
===================================================== */

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.product_serials')
      AND name = 'note'
)
BEGIN
    ALTER TABLE dbo.product_serials
    ADD note NVARCHAR(500) NULL;
END
GO

/* =====================================================
   BƯỚC 3: Tạo proc cập nhật thông tin Serial/IMEI
   Dùng cho:
   - Bổ sung IMEI
   - Cập nhật giá bán riêng
   - Cập nhật ghi chú ngoại hình / pin / màu / tình trạng
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_UpdateSerialInfo', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_UpdateSerialInfo;
GO

CREATE PROC dbo.ProductSerials_UpdateSerialInfo
    @serial_id INT,
    @serial_number NVARCHAR(100) = NULL,
    @sell_price_override DECIMAL(18, 0) = NULL,
    @note NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
    )
    BEGIN
        RAISERROR(N'Không tìm thấy dòng Serial/IMEI cần cập nhật.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
          AND status <> 0
    )
    BEGIN
        RAISERROR(N'Không thể cập nhật thông tin cho sản phẩm đã bán.', 16, 1);
        RETURN;
    END

    IF @serial_number IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM dbo.product_serials
            WHERE serial_number = @serial_number
              AND serial_id <> @serial_id
        )
        BEGIN
            RAISERROR(N'Serial/IMEI này đã tồn tại trong hệ thống.', 16, 1);
            RETURN;
        END
    END

    IF @sell_price_override IS NOT NULL AND @sell_price_override < 0
    BEGIN
        RAISERROR(N'Giá bán riêng không hợp lệ.', 16, 1);
        RETURN;
    END

    UPDATE dbo.product_serials
    SET
        serial_number = @serial_number,
        sell_price_override = @sell_price_override,
        note = @note
    WHERE serial_id = @serial_id
      AND status = 0;
END
GO

/* =====================================================
   BƯỚC 4: Cập nhật proc bổ sung IMEI cũ
   Giữ lại để code cũ vẫn chạy được
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_UpdateBlankSerial', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_UpdateBlankSerial;
GO

CREATE PROC dbo.ProductSerials_UpdateBlankSerial
    @serial_id INT,
    @serial_number NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');

    IF @serial_number IS NULL
    BEGIN
        RAISERROR(N'Vui lòng nhập Serial/IMEI.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
    )
    BEGIN
        RAISERROR(N'Không tìm thấy dòng Serial/IMEI cần cập nhật.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_number = @serial_number
          AND serial_id <> @serial_id
    )
    BEGIN
        RAISERROR(N'Serial/IMEI này đã tồn tại trong hệ thống.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
          AND status <> 0
    )
    BEGIN
        RAISERROR(N'Không thể cập nhật IMEI cho sản phẩm đã bán.', 16, 1);
        RETURN;
    END

    UPDATE dbo.product_serials
    SET serial_number = @serial_number
    WHERE serial_id = @serial_id
      AND status = 0;
END
GO

/* =====================================================
   BƯỚC 5: Cập nhật proc lấy Serial còn trong kho
   Có thêm giá bán riêng và ghi chú
===================================================== */

IF OBJECT_ID(N'dbo.ProductSerials_GetAvailable', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_GetAvailable;
GO

CREATE PROC dbo.ProductSerials_GetAvailable
    @product_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        serial_id,
        product_id,
        import_id,
        serial_number,
        status,
        sell_price_override,
        note,
        created_at
    FROM dbo.product_serials
    WHERE product_id = @product_id
      AND status = 0
      AND serial_number IS NOT NULL
    ORDER BY serial_id DESC;
END
GO

/* =====================================================
   BƯỚC 6: Cập nhật proc truy xuất nguồn gốc Serial
   Hiển thị thêm giá bán riêng và ghi chú
===================================================== */

IF OBJECT_ID(N'dbo.Products_GetSerialTraceability', N'P') IS NOT NULL
    DROP PROC dbo.Products_GetSerialTraceability;
GO

CREATE PROC dbo.Products_GetSerialTraceability
    @ProductId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ps.serial_id,
        ps.import_id,
        ps.order_id,

        ISNULL(ps.serial_number, N'Chưa cập nhật') AS [Mã Serial / IMEI],

        i.import_code AS [Mã phiếu nhập],
        CONVERT(VARCHAR(10), i.import_date, 103) AS [Ngày nhập],

        ISNULL(sup.supplier_name, N'Không xác định') AS [Nhà cung cấp],

        ps.sell_price_override AS [Giá bán riêng],
        ISNULL(ps.note, N'') AS [Ghi chú],

        CASE 
            WHEN ps.status = 0 THEN N'🟢 Trong kho'
            ELSE N'🔴 Đã bán'
        END AS [Trạng thái],

        ISNULL(o.order_code, N'') AS [Mã đơn bán],

        CASE 
            WHEN o.order_date IS NOT NULL THEN CONVERT(VARCHAR(10), o.order_date, 103)
            ELSE N''
        END AS [Ngày bán]

    FROM dbo.product_serials ps
    INNER JOIN dbo.imports i 
        ON ps.import_id = i.import_id
    LEFT JOIN dbo.suppliers sup 
        ON i.supplier_id = sup.supplier_id
    LEFT JOIN dbo.orders o 
        ON ps.order_id = o.order_id
    WHERE ps.product_id = @ProductId
    ORDER BY ps.serial_id DESC;
END
GO






IF OBJECT_ID(N'dbo.ProductSerials_GetTraceability', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_GetTraceability;
GO

CREATE PROC dbo.ProductSerials_GetTraceability
    @serial_number NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        ps.serial_id AS SerialId,
        ps.product_id AS ProductId,
        ps.serial_number AS SerialNumber,
        ps.import_id AS ImportId,
        ps.order_id AS OrderId,
        ps.status AS Status,
        ps.created_at AS CreatedAt,

        ps.sell_price_override AS SellPriceOverride,
        ps.note AS Note,

        p.product_name AS ProductName,
        s.supplier_name AS SupplierName,
        i.import_date AS ImportDate,
        i.import_code AS ImportCode,
        c.name AS CustomerName,
        o.order_date AS OrderDate,
        o.order_code AS OrderCode
    FROM dbo.product_serials ps
    INNER JOIN dbo.products p 
        ON ps.product_id = p.product_id
    LEFT JOIN dbo.imports i 
        ON ps.import_id = i.import_id
    LEFT JOIN dbo.suppliers s 
        ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.orders o 
        ON ps.order_id = o.order_id
    LEFT JOIN dbo.customers c 
        ON o.customer_id = c.customer_id
    WHERE ps.serial_number = @serial_number;
END
GO



/* =====================================================
   PATCH: Thêm màu cho từng Serial/IMEI
===================================================== */

SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.product_serials')
      AND name = 'product_color'
)
BEGIN
    ALTER TABLE dbo.product_serials
    ADD product_color NVARCHAR(50) NULL;
END
GO



IF OBJECT_ID(N'dbo.ProductSerials_UpdateSerialInfo', N'P') IS NOT NULL
    DROP PROC dbo.ProductSerials_UpdateSerialInfo;
GO

CREATE PROC dbo.ProductSerials_UpdateSerialInfo
    @serial_id INT,
    @serial_number NVARCHAR(100) = NULL,
    @sell_price_override DECIMAL(18, 0) = NULL,
    @product_color NVARCHAR(50) = NULL,
    @note NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');
    SET @product_color = NULLIF(LTRIM(RTRIM(@product_color)), N'');
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
    )
    BEGIN
        RAISERROR(N'Không tìm thấy dòng Serial/IMEI cần cập nhật.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_id = @serial_id
          AND status <> 0
    )
    BEGIN
        RAISERROR(N'Không thể cập nhật thông tin cho sản phẩm đã bán.', 16, 1);
        RETURN;
    END

    IF @serial_number IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM dbo.product_serials
            WHERE serial_number = @serial_number
              AND serial_id <> @serial_id
        )
        BEGIN
            RAISERROR(N'Serial/IMEI này đã tồn tại trong hệ thống.', 16, 1);
            RETURN;
        END
    END

    IF @sell_price_override IS NOT NULL AND @sell_price_override < 0
    BEGIN
        RAISERROR(N'Giá bán riêng không hợp lệ.', 16, 1);
        RETURN;
    END

    UPDATE dbo.product_serials
    SET
        serial_number = @serial_number,
        sell_price_override = @sell_price_override,
        product_color = @product_color,
        note = @note
    WHERE serial_id = @serial_id
      AND status = 0;
END
GO




ALTER PROC [dbo].[ProductSerials_GetTraceability]
    @serial_number NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        ps.serial_id AS SerialId,
        ps.product_id AS ProductId,
        ps.serial_number AS SerialNumber,
        ps.import_id AS ImportId,
        ps.order_id AS OrderId,
        ps.status AS Status,
        ps.created_at AS CreatedAt,

        ps.sell_price_override AS SellPriceOverride,
        ps.product_color AS ProductColor,
        ps.note AS Note,

        p.product_name AS ProductName,
        s.supplier_name AS SupplierName,
        i.import_date AS ImportDate,
        i.import_code AS ImportCode,
        c.name AS CustomerName,
        o.order_date AS OrderDate,
        o.order_code AS OrderCode
    FROM dbo.product_serials ps
    INNER JOIN dbo.products p 
        ON ps.product_id = p.product_id
    LEFT JOIN dbo.imports i 
        ON ps.import_id = i.import_id
    LEFT JOIN dbo.suppliers s 
        ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.orders o 
        ON ps.order_id = o.order_id
    LEFT JOIN dbo.customers c 
        ON o.customer_id = c.customer_id
    WHERE ps.serial_number = @serial_number;
END
GO




CREATE OR ALTER PROC dbo.Products_GetSerialTraceability
    @ProductId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ps.serial_id,
        ps.import_id,
        ps.order_id,

        ISNULL(ps.serial_number, N'Chưa cập nhật') AS [Mã Serial / IMEI],

        i.import_code AS [Mã phiếu nhập],
        CONVERT(VARCHAR(10), i.import_date, 103) AS [Ngày nhập],

        ISNULL(sup.supplier_name, N'Không xác định') AS [Nhà cung cấp],

        ps.sell_price_override AS [Giá bán riêng],
        ISNULL(ps.product_color, N'') AS [Màu],
        ISNULL(ps.note, N'') AS [Ghi chú],

        CASE 
            WHEN ps.status = 0 THEN N'🟢 Trong kho'
            ELSE N'🔴 Đã bán'
        END AS [Trạng thái],

        ISNULL(o.order_code, N'') AS [Mã đơn bán],

        CASE 
            WHEN o.order_date IS NOT NULL THEN CONVERT(VARCHAR(10), o.order_date, 103)
            ELSE N''
        END AS [Ngày bán]

    FROM dbo.product_serials ps
    INNER JOIN dbo.imports i 
        ON ps.import_id = i.import_id
    LEFT JOIN dbo.suppliers sup 
        ON i.supplier_id = sup.supplier_id
    LEFT JOIN dbo.orders o 
        ON ps.order_id = o.order_id
    WHERE ps.product_id = @ProductId
    ORDER BY ps.serial_id DESC;
END
GO





CREATE OR ALTER PROCEDURE dbo.Orders_Cancel
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.orders
            WHERE order_id = @OrderId
        )
        BEGIN
            RAISERROR(N'Không tìm thấy hóa đơn cần hủy.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        UPDATE dbo.orders
        SET status = 'Cancelled'
        WHERE order_id = @OrderId;

        -- Khôi phục Serial/IMEI về kho
        UPDATE dbo.product_serials
        SET 
            status = 0,
            order_id = NULL
        WHERE order_id = @OrderId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO




CREATE OR ALTER PROCEDURE dbo.Orders_Delete
    @OrderId INT
AS
BEGIN
    SET NOCOUNT OFF;

    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @Status NVARCHAR(50);

        SELECT @Status = status
        FROM dbo.orders
        WHERE order_id = @OrderId;

        IF @Status IS NULL
        BEGIN
            RAISERROR(N'Không tìm thấy hóa đơn cần xóa.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @Status NOT IN ('Pending', 'Cancelled')
        BEGIN
            RAISERROR(N'Chỉ được xóa hóa đơn Tạm tính hoặc Đã hủy. Vui lòng hủy hóa đơn trước khi xóa.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Phòng trường hợp hóa đơn đã hủy nhưng serial vẫn còn trỏ order_id
        UPDATE dbo.product_serials
        SET 
            status = 0,
            order_id = NULL
        WHERE order_id = @OrderId;

        DELETE FROM dbo.order_items
        WHERE order_id = @OrderId;

        DELETE FROM dbo.orders
        WHERE order_id = @OrderId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO
