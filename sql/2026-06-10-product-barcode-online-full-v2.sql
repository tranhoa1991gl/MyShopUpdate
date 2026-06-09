/*
    MyShop Online SQL Migration V2 - Barcode
    Mục đích: vá mã vạch sản phẩm cho cơ chế OnlineSqlUpdater.
    Bản V2 không dùng GO và không dùng CREATE OR ALTER ở cấp batch chính.
*/

SET NOCOUNT ON;


/* =========================================================
   1. Thêm cột barcode nếu chưa có
   ========================================================= */
IF COL_LENGTH('dbo.products', 'barcode') IS NULL
BEGIN
    ALTER TABLE dbo.products ADD barcode NVARCHAR(100) NULL;
    PRINT N'Đã thêm cột dbo.products.barcode.';
END
ELSE
BEGIN
    PRINT N'Cột dbo.products.barcode đã tồn tại.';
END


/* =========================================================
   2. Chuẩn hóa dữ liệu barcode cũ
   ========================================================= */
UPDATE dbo.products
SET barcode = NULLIF(LTRIM(RTRIM(ISNULL(barcode, N''))), N'')
WHERE barcode IS NOT NULL;


/* =========================================================
   3. Bỏ index thường cũ nếu có, vì sẽ dùng unique index
   ========================================================= */
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_products_barcode'
      AND object_id = OBJECT_ID('dbo.products')
)
BEGIN
    DROP INDEX IX_products_barcode ON dbo.products;
    PRINT N'Đã xóa IX_products_barcode cũ để chuyển sang unique index.';
END


/* =========================================================
   4. Cập nhật stored procedure liên quan sản phẩm
   ========================================================= */


IF OBJECT_ID(N'[dbo].[Products_All]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_All];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_All]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.barcode       AS Barcode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        ISNULL(c.category_name, N''Chưa phân loại'') AS CategoryName,
        p.unit_id       AS UnitId,
        ISNULL(u.unit_name, '''') AS UnitName,
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        ISNULL(p.import_price, 0) AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0) AS HasSerial,
        p.image_path    AS ImagePath,
        ISNULL((
            SELECT SUM(oi.quantity)
            FROM order_items oi
            INNER JOIN orders o ON oi.order_id = o.order_id
            WHERE oi.product_id = p.product_id
              AND o.status != ''Cancelled''
        ), 0) AS TotalQuantitySold
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    LEFT JOIN dbo.units u ON p.unit_id = u.unit_id
    ORDER BY p.product_name;
END');


IF OBJECT_ID(N'[dbo].[Products_GetAvailable]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_GetAvailable];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_GetAvailable]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        product_id      AS ProductId,
        product_code    AS ProductCode,
        barcode         AS Barcode,
        product_name    AS ProductName,
        category_id     AS CategoryId,
        stock           AS Stock,
        sell_price      AS SellPrice,
        created_at      AS CreatedAt,
        ''''              AS Unit,
        0               AS CostPrice,
        image_path      AS ImagePath,
        ISNULL(warranty_months, 0) AS WarrantyMonths,
        ISNULL(has_serial, 0) AS HasSerial
    FROM dbo.products
    WHERE is_active = 1
    ORDER BY product_name ASC;
END');


IF OBJECT_ID(N'[dbo].[Products_GetById]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_GetById];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_GetById]
    @product_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.barcode       AS Barcode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        ISNULL(c.category_name, N''Chưa phân loại'') AS CategoryName,
        p.unit_id       AS UnitId,
        ISNULL(u.unit_name, '''') AS UnitName,
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        ISNULL(p.import_price, 0) AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0) AS HasSerial,
        p.image_path    AS ImagePath
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    LEFT JOIN dbo.units u ON p.unit_id = u.unit_id
    WHERE p.product_id = @product_id;
END');


IF OBJECT_ID(N'[dbo].[Products_Insert]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_Insert];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_Insert]
    @ProductCode NVARCHAR(50),
    @ProductName NVARCHAR(150),
    @CategoryId INT,
    @UnitId INT,
    @SellPrice DECIMAL(12,2),
    @ImportPrice DECIMAL(18,0),
    @Stock INT,
    @IsActive BIT,
    @WarrantyMonths INT,
    @HasSerial BIT,
    @ImagePath NVARCHAR(500),
    @Barcode NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), N'''');

    INSERT INTO dbo.products
    (
        product_code, barcode, product_name, category_id, unit_id,
        sell_price, import_price, stock, is_active, created_at,
        warranty_months, has_serial, image_path
    )
    VALUES
    (
        @ProductCode, @Barcode, @ProductName, @CategoryId, @UnitId,
        @SellPrice, @ImportPrice, @Stock, @IsActive, GETDATE(),
        @WarrantyMonths, @HasSerial, @ImagePath
    );

    SELECT SCOPE_IDENTITY();
END');


IF OBJECT_ID(N'[dbo].[Products_Update]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_Update];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_Update]
    @ProductId INT,
    @ProductCode NVARCHAR(50),
    @ProductName NVARCHAR(150),
    @CategoryId INT,
    @UnitId INT,
    @SellPrice DECIMAL(12,2),
    @ImportPrice DECIMAL(18,0),
    @Stock INT,
    @IsActive BIT,
    @WarrantyMonths INT,
    @HasSerial BIT,
    @ImagePath NVARCHAR(500),
    @Barcode NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Barcode = NULLIF(LTRIM(RTRIM(@Barcode)), N'''');

    UPDATE dbo.products
    SET product_code = @ProductCode,
        barcode = @Barcode,
        product_name = @ProductName,
        category_id = @CategoryId,
        unit_id = @UnitId,
        sell_price = @SellPrice,
        import_price = @ImportPrice,
        stock = @Stock,
        is_active = @IsActive,
        warranty_months = @WarrantyMonths,
        has_serial = @HasSerial,
        image_path = @ImagePath
    WHERE product_id = @ProductId;
END');


IF OBJECT_ID(N'[dbo].[Products_Search]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_Search];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_Search]
    @Keyword NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.barcode       AS Barcode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        c.category_name AS CategoryName,
        p.unit_id       AS UnitId,
        ISNULL(u.unit_name, '''') AS UnitName,
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        p.import_price  AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0) AS HasSerial,
        p.image_path    AS ImagePath
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    LEFT JOIN dbo.units u ON p.unit_id = u.unit_id
    WHERE p.is_active = 1
      AND (
            @Keyword = N''''
         OR p.product_name LIKE N''%'' + @Keyword + N''%''
         OR p.product_code LIKE N''%'' + @Keyword + N''%''
         OR ISNULL(p.barcode, N'''') LIKE N''%'' + @Keyword + N''%''
      )
    ORDER BY p.product_name;
END');


IF OBJECT_ID(N'[dbo].[Products_SearchByKeywordAndCategory]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_SearchByKeywordAndCategory];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_SearchByKeywordAndCategory]
    @Keyword NVARCHAR(200),
    @CategoryId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        p.barcode AS Barcode,
        p.product_name AS ProductName,
        p.category_id AS CategoryId,
        p.sell_price AS SellPrice,
        p.stock AS Stock,
        p.is_active AS IsActive,
        p.created_at AS CreatedAt,
        p.import_price AS ImportPrice,
        p.unit_id AS UnitId,
        p.warranty_months AS WarrantyMonths,
        p.has_serial AS HasSerial,
        p.image_path AS ImagePath,
        c.category_name AS CategoryName
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    WHERE p.is_active = 1
      AND p.stock > 0
      AND (@CategoryId = 0 OR p.category_id = @CategoryId)
      AND (
            @Keyword = N''''
         OR p.product_name LIKE N''%'' + @Keyword + N''%''
         OR p.product_code LIKE N''%'' + @Keyword + N''%''
         OR ISNULL(p.barcode, N'''') LIKE N''%'' + @Keyword + N''%''
      )
    ORDER BY p.product_name;
END');


IF OBJECT_ID(N'[dbo].[Products_SearchForImport]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_SearchForImport];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_SearchForImport]
    @Keyword NVARCHAR(200),
    @CategoryId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        p.barcode AS Barcode,
        p.product_name AS ProductName,
        p.category_id AS CategoryId,
        p.sell_price AS SellPrice,
        p.stock AS Stock,
        p.is_active AS IsActive,
        p.created_at AS CreatedAt,
        p.import_price AS ImportPrice,
        p.unit_id AS UnitId,
        p.warranty_months AS WarrantyMonths,
        p.has_serial AS HasSerial,
        p.image_path AS ImagePath,
        c.category_name AS CategoryName
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    WHERE p.is_active = 1
      AND (@CategoryId = 0 OR p.category_id = @CategoryId)
      AND (
            @Keyword = N''''
         OR p.product_name LIKE N''%'' + @Keyword + N''%''
         OR p.product_code LIKE N''%'' + @Keyword + N''%''
         OR ISNULL(p.barcode, N'''') LIKE N''%'' + @Keyword + N''%''
      )
    ORDER BY p.product_name;
END');


IF OBJECT_ID(N'[dbo].[Products_GetSalesStatistics]', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[Products_GetSalesStatistics];
END;

EXEC(N'CREATE PROCEDURE [dbo].[Products_GetSalesStatistics]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        p.barcode AS Barcode,
        p.product_name AS ProductName,
        p.category_id AS CategoryId,
        ISNULL(c.category_name, N''Chưa phân loại'') AS CategoryName,
        p.unit_id AS UnitId,
        ISNULL(u.unit_name, '''') AS UnitName,
        p.sell_price AS SellPrice,
        p.stock AS Stock,
        p.is_active AS IsActive,
        p.created_at AS CreatedAt,
        ISNULL(p.import_price, 0) AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0) AS HasSerial,
        p.image_path AS ImagePath,
        ISNULL(SUM(CASE WHEN ord.status != ''Cancelled'' THEN o.quantity ELSE 0 END), 0) AS TotalQuantitySold
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    LEFT JOIN dbo.units u ON p.unit_id = u.unit_id
    LEFT JOIN dbo.order_items o ON p.product_id = o.product_id
    LEFT JOIN dbo.orders ord ON o.order_id = ord.order_id
    GROUP BY p.product_id, p.product_code, p.barcode, p.product_name, p.category_id, c.category_name,
        p.unit_id, u.unit_name, p.sell_price, p.stock, p.is_active, p.created_at, p.import_price,
        p.warranty_months, p.has_serial, p.image_path
    ORDER BY TotalQuantitySold DESC;
END');


/* =========================================================
   5. Tạo unique index cho barcode nếu dữ liệu không bị trùng
   ========================================================= */

-- Chỉ tạo khi chưa có UX_products_barcode
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_products_barcode'
      AND object_id = OBJECT_ID('dbo.products')
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dbo.products
        WHERE barcode IS NOT NULL
          AND LTRIM(RTRIM(barcode)) <> N''
        GROUP BY barcode
        HAVING COUNT(*) > 1
    )
    BEGIN
        PRINT N'Đang có mã vạch bị trùng. Script bỏ qua tạo UNIQUE INDEX UX_products_barcode.';
        PRINT N'Hãy xử lý các mã vạch trùng bên dưới rồi chạy lại script này.';

        SELECT
            barcode AS [MaVachTrung],
            COUNT(*) AS [SoSanPhamTrung]
        FROM dbo.products
        WHERE barcode IS NOT NULL
          AND LTRIM(RTRIM(barcode)) <> N''
        GROUP BY barcode
        HAVING COUNT(*) > 1
        ORDER BY barcode;

        SELECT
            p.product_id AS ProductId,
            p.product_code AS ProductCode,
            p.barcode AS Barcode,
            p.product_name AS ProductName
        FROM dbo.products p
        INNER JOIN (
            SELECT barcode
            FROM dbo.products
            WHERE barcode IS NOT NULL
              AND LTRIM(RTRIM(barcode)) <> N''
            GROUP BY barcode
            HAVING COUNT(*) > 1
        ) d ON d.barcode = p.barcode
        ORDER BY p.barcode, p.product_id;
    END
    ELSE
    BEGIN
        CREATE UNIQUE INDEX UX_products_barcode
        ON dbo.products(barcode)
        WHERE barcode IS NOT NULL AND barcode <> N'';

        PRINT N'Đã tạo UNIQUE INDEX UX_products_barcode. Barcode có nhập sẽ không được trùng.';
    END
END
ELSE
BEGIN
    PRINT N'UNIQUE INDEX UX_products_barcode đã tồn tại.';
END


/* =========================================================
   6. Kiểm tra kết quả cuối
   ========================================================= */
SELECT
    CASE WHEN COL_LENGTH('dbo.products', 'barcode') IS NOT NULL
         THEN N'OK - Đã có cột barcode'
         ELSE N'LỖI - Chưa có cột barcode'
    END AS [CotBarcode],
    CASE WHEN EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'UX_products_barcode'
          AND object_id = OBJECT_ID('dbo.products')
    ) THEN N'OK - Đã có unique index barcode'
      ELSE N'CHƯA TẠO UNIQUE INDEX - có thể còn barcode trùng'
    END AS [UniqueIndexBarcode];
