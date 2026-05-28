
-- =========================================================
-- 1. THÊM CỘT 'image_path' VÀO BẢNG products
-- =========================================================
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[products]') AND name = 'image_path')
BEGIN
    ALTER TABLE [dbo].[products] ADD [image_path] NVARCHAR(500) NULL;
END
GO

-- =========================================================
-- 2. CẬP NHẬT THỦ TỤC THÊM (INSERT)
-- =========================================================
ALTER PROCEDURE [dbo].[Products_Insert]
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
    @ImagePath NVARCHAR(500) -- [MỚI BỔ SUNG]
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Products (product_code, product_name, category_id, unit_id, sell_price, import_price, stock, is_active, created_at, warranty_months, has_serial, image_path)
    VALUES (@ProductCode, @ProductName, @CategoryId, @UnitId, @SellPrice, @ImportPrice, @Stock, @IsActive, GETDATE(), @WarrantyMonths, @HasSerial, @ImagePath);
    
    SELECT SCOPE_IDENTITY();
END
GO

-- =========================================================
-- 3. CẬP NHẬT THỦ TỤC SỬA (UPDATE)
-- =========================================================
ALTER PROCEDURE [dbo].[Products_Update]
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
    @ImagePath NVARCHAR(500) -- [MỚI BỔ SUNG]
AS
BEGIN
    UPDATE Products
    SET product_code = @ProductCode,
        product_name = @ProductName,
        category_id = @CategoryId,
        unit_id = @UnitId,
        sell_price = @SellPrice,
        import_price = @ImportPrice,
        stock = @Stock,
        is_active = @IsActive,
        warranty_months = @WarrantyMonths,
        has_serial = @HasSerial,
        image_path = @ImagePath  -- [MỚI BỔ SUNG]
    WHERE product_id = @ProductId
END
GO

-- =========================================================
-- 4. CẬP NHẬT CÁC THỦ TỤC LẤY DỮ LIỆU (SELECT / SEARCH)
-- =========================================================

-- Lấy tất cả
ALTER PROCEDURE [dbo].[Products_All]
AS
BEGIN
    SELECT 
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        ISNULL(c.category_name, N'Chưa phân loại') AS CategoryName,
        p.unit_id       AS UnitId,       
        ISNULL(u.unit_name, '') AS UnitName,     
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        ISNULL(p.import_price, 0) AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0)      AS HasSerial,
        p.image_path    AS ImagePath, -- [MỚI BỔ SUNG]

        ISNULL((
            SELECT SUM(oi.quantity) 
            FROM order_items oi 
            INNER JOIN orders o ON oi.order_id = o.order_id
            WHERE oi.product_id = p.product_id 
              AND o.status != 'Cancelled'
        ), 0) AS TotalQuantitySold
    FROM Products p
    LEFT JOIN Categories c ON p.category_id = c.category_id
    LEFT JOIN Units u      ON p.unit_id = u.unit_id
    ORDER BY p.product_name
END
GO

-- Lấy theo ID
ALTER PROCEDURE [dbo].[Products_GetById]
    @product_id int
AS
BEGIN
    SELECT
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        ISNULL(c.category_name, N'Chưa phân loại') AS CategoryName,
        p.unit_id       AS UnitId,
        ISNULL(u.unit_name, '') AS UnitName,
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        ISNULL(p.import_price, 0) AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0)      AS HasSerial,
        p.image_path    AS ImagePath -- [MỚI BỔ SUNG]
    FROM Products p
    LEFT JOIN Categories c ON p.category_id = c.category_id
    LEFT JOIN Units u      ON p.unit_id = u.unit_id
    WHERE p.product_id = @product_id
END
GO

-- Lấy sản phẩm khả dụng (Sửa lại thuộc tính ImagePath bị fix cứng thành rỗng)
ALTER PROCEDURE [dbo].[Products_GetAvailable]
AS
BEGIN
    SELECT 
        product_id      AS ProductId, 
        product_code    AS ProductCode,
        product_name    AS ProductName, 
        category_id     AS CategoryId,
        stock           AS Stock, 
        sell_price      AS SellPrice, 
        created_at      AS CreatedAt,
        ''              AS Unit,        
        0               AS CostPrice,   
        image_path      AS ImagePath,   -- [ĐÃ SỬA LẠI THAY VÌ '']
        ISNULL(warranty_months, 0) AS WarrantyMonths,
        ISNULL(has_serial, 0)      AS HasSerial
    FROM products 
    WHERE is_active = 1 
    ORDER BY product_name ASC 
END
GO

-- Tìm kiếm thông thường
ALTER PROCEDURE [dbo].[Products_Search]
    @Keyword NVARCHAR(100)
AS
BEGIN
    SELECT
        p.product_id    AS ProductId,
        p.product_code  AS ProductCode,
        p.product_name  AS ProductName,
        p.category_id   AS CategoryId,
        c.category_name AS CategoryName,
        p.unit_id       AS UnitId,
        ISNULL(u.unit_name, '') AS UnitName,
        p.sell_price    AS SellPrice,
        p.stock         AS Stock,
        p.is_active     AS IsActive,
        p.created_at    AS CreatedAt,
        p.import_price  AS ImportPrice,
        ISNULL(p.warranty_months, 0) AS WarrantyMonths,
        ISNULL(p.has_serial, 0)      AS HasSerial,
        p.image_path    AS ImagePath -- [MỚI BỔ SUNG]
    FROM Products p
    LEFT JOIN Categories c ON p.category_id = c.category_id
    LEFT JOIN Units u      ON p.unit_id = u.unit_id
    WHERE p.is_active = 1
      AND (
            p.product_name LIKE '%' + @Keyword + '%'
         OR p.product_code LIKE '%' + @Keyword + '%'
      )
    ORDER BY p.product_name
END
GO

-- Tìm kiếm theo danh mục (Sửa 2 cái cùng lúc)
ALTER PROCEDURE [dbo].[Products_SearchByKeywordAndCategory]
    @Keyword NVARCHAR(200),
    @CategoryId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        p.product_id AS ProductId, p.product_code AS ProductCode, p.product_name AS ProductName,
        p.category_id AS CategoryId, p.sell_price AS SellPrice, p.stock AS Stock,
        p.is_active AS IsActive, p.created_at AS CreatedAt, p.import_price AS ImportPrice,
        p.unit_id AS UnitId, p.warranty_months AS WarrantyMonths, p.has_serial AS HasSerial,
        p.image_path AS ImagePath, c.category_name AS CategoryName 
    FROM products p
    LEFT JOIN categories c ON p.category_id = c.category_id
    WHERE p.is_active = 1 AND p.stock > 0 
      AND (@CategoryId = 0 OR p.category_id = @CategoryId)
      AND (@Keyword = '' OR p.product_name LIKE N'%' + @Keyword + '%' OR p.product_code LIKE N'%' + @Keyword + '%')
    ORDER BY p.product_name
END
GO

ALTER PROCEDURE [dbo].[Products_SearchForImport]
    @Keyword NVARCHAR(200),
    @CategoryId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        p.product_id AS ProductId, p.product_code AS ProductCode, p.product_name AS ProductName,
        p.category_id AS CategoryId, p.sell_price AS SellPrice, p.stock AS Stock,
        p.is_active AS IsActive, p.created_at AS CreatedAt, p.import_price AS ImportPrice,
        p.unit_id AS UnitId, p.warranty_months AS WarrantyMonths, p.has_serial AS HasSerial,
        p.image_path AS ImagePath, c.category_name AS CategoryName 
    FROM products p
    LEFT JOIN categories c ON p.category_id = c.category_id
    WHERE p.is_active = 1
      AND (@CategoryId = 0 OR p.category_id = @CategoryId)
      AND (@Keyword = '' OR p.product_name LIKE N'%' + @Keyword + '%' OR p.product_code LIKE N'%' + @Keyword + '%')
    ORDER BY p.product_name
END
GO

ALTER PROCEDURE [dbo].[Products_GetSalesStatistics]
AS
BEGIN
    SET NOCOUNT ON; 
    SELECT 
        p.product_id AS ProductId, p.product_code AS ProductCode, p.product_name AS ProductName,
        p.category_id AS CategoryId, ISNULL(c.category_name, N'Chưa phân loại') AS CategoryName,
        p.unit_id AS UnitId, ISNULL(u.unit_name, '') AS UnitName,
        p.sell_price AS SellPrice, p.stock AS Stock, p.is_active AS IsActive,
        p.created_at AS CreatedAt, ISNULL(p.import_price, 0) AS ImportPrice, 
        ISNULL(p.warranty_months, 0) AS WarrantyMonths, ISNULL(p.has_serial, 0) AS HasSerial,
        p.image_path AS ImagePath,
        ISNULL(SUM(CASE WHEN ord.status != 'Cancelled' THEN o.quantity ELSE 0 END), 0) AS TotalQuantitySold
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON p.category_id = c.category_id
    LEFT JOIN dbo.units u ON p.unit_id = u.unit_id
    LEFT JOIN dbo.order_items o ON p.product_id = o.product_id
    LEFT JOIN dbo.orders ord ON o.order_id = ord.order_id 
    GROUP BY p.product_id, p.product_code, p.product_name, p.category_id, c.category_name,
        p.unit_id, u.unit_name, p.sell_price, p.stock, p.is_active, p.created_at, p.import_price,
        p.warranty_months, p.has_serial, p.image_path
    ORDER BY TotalQuantitySold DESC 
END
GO