USE [DBMyShop]
GO
SET NOCOUNT ON;
GO

/* Fix 10 - Đồng bộ bảng lưu Serial/IMEI trả nhà cung cấp */
IF OBJECT_ID(N'dbo.purchase_return_serials', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_return_serials
    (
        return_serial_id INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_purchase_return_serials PRIMARY KEY,
        return_id INT NOT NULL,
        return_detail_id INT NOT NULL,
        serial_id INT NOT NULL,
        serial_number NVARCHAR(100) NOT NULL,
        created_at DATETIME NOT NULL
            CONSTRAINT DF_purchase_return_serials_created DEFAULT (GETDATE())
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
      AND name = N'IX_purchase_return_serials_return'
)
    CREATE INDEX IX_purchase_return_serials_return
    ON dbo.purchase_return_serials(return_id);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
      AND name = N'IX_purchase_return_serials_detail'
)
    CREATE INDEX IX_purchase_return_serials_detail
    ON dbo.purchase_return_serials(return_detail_id);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.purchase_return_serials')
      AND name = N'IX_purchase_return_serials_serial'
)
    CREATE INDEX IX_purchase_return_serials_serial
    ON dbo.purchase_return_serials(serial_id);
GO

/* Đồng bộ hiển thị truy vết trạng thái Serial/IMEI. */
IF OBJECT_ID(N'dbo.Products_GetSerialTraceability', N'P') IS NOT NULL
BEGIN
    EXEC(N'ALTER PROCEDURE [dbo].[Products_GetSerialTraceability]
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
                ELSE N''⚪ Không xác định''
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
GO
