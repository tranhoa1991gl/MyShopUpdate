SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- Các chỉ mục phục vụ kiểm tra chứng từ gốc đã phát sinh phiếu trả.
IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.orders', N'original_order_id') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE object_id = OBJECT_ID(N'dbo.orders')
         AND name = N'IX_orders_original_order_status'
   )
BEGIN
    CREATE INDEX IX_orders_original_order_status
        ON dbo.orders(original_order_id, order_type, status)
        INCLUDE(order_id);
END;

IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.purchase_returns', N'import_id') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE object_id = OBJECT_ID(N'dbo.purchase_returns')
         AND name = N'IX_purchase_returns_import_status'
   )
BEGIN
    CREATE INDEX IX_purchase_returns_import_status
        ON dbo.purchase_returns(import_id, status)
        INCLUDE(return_id);
END;

IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.order_items', N'original_order_item_id') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE object_id = OBJECT_ID(N'dbo.order_items')
         AND name = N'IX_order_items_original_order_item'
   )
BEGIN
    CREATE INDEX IX_order_items_original_order_item
        ON dbo.order_items(original_order_item_id, order_id)
        INCLUDE(base_quantity, quantity, gift_quantity);
END;

-- Bốn khóa ngoại dưới đây từng được tạo bằng WITH NOCHECK.
-- Chỉ chuyển sang trạng thái trusted sau khi chắc chắn không có dữ liệu mồ côi.
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_import_details_product_variants')
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM dbo.import_details d
        LEFT JOIN dbo.product_variants v ON v.variant_id = d.product_variant_id
        WHERE d.product_variant_id IS NOT NULL AND v.variant_id IS NULL
    )
        THROW 51101, N'Không thể xác thực FK_import_details_product_variants vì còn dữ liệu mồ côi.', 1;

    ALTER TABLE dbo.import_details WITH CHECK CHECK CONSTRAINT FK_import_details_product_variants;
END;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_import_details_units')
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM dbo.import_details d
        LEFT JOIN dbo.Units u ON u.unit_id = d.unit_id
        WHERE d.unit_id IS NOT NULL AND u.unit_id IS NULL
    )
        THROW 51102, N'Không thể xác thực FK_import_details_units vì còn dữ liệu mồ côi.', 1;

    ALTER TABLE dbo.import_details WITH CHECK CHECK CONSTRAINT FK_import_details_units;
END;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_order_items_product_variants')
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM dbo.order_items d
        LEFT JOIN dbo.product_variants v ON v.variant_id = d.product_variant_id
        WHERE d.product_variant_id IS NOT NULL AND v.variant_id IS NULL
    )
        THROW 51103, N'Không thể xác thực FK_order_items_product_variants vì còn dữ liệu mồ côi.', 1;

    ALTER TABLE dbo.order_items WITH CHECK CHECK CONSTRAINT FK_order_items_product_variants;
END;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_order_items_units')
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM dbo.order_items d
        LEFT JOIN dbo.Units u ON u.unit_id = d.unit_id
        WHERE d.unit_id IS NOT NULL AND u.unit_id IS NULL
    )
        THROW 51104, N'Không thể xác thực FK_order_items_units vì còn dữ liệu mồ côi.', 1;

    ALTER TABLE dbo.order_items WITH CHECK CHECK CONSTRAINT FK_order_items_units;
END;

COMMIT TRANSACTION;

