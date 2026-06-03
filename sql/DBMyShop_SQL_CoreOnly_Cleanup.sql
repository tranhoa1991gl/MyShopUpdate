

/*
    DBMyShop - Core-only cleanup patch
    Mục tiêu:
    1) Gỡ các procedure thuộc nhánh biến thể/lô/hạn dùng không được C# hiện tại gọi.
    2) Thêm lại các procedure C# hiện tại đang gọi nhưng SQL đang thiếu.

    LƯU Ý:
    - Script này KHÔNG xóa bảng dữ liệu để tránh mất dữ liệu.
    - Nếu muốn xóa bảng/cột biến thể, xem phần OPTIONAL ở cuối và chỉ chạy sau khi backup DB.
*/

/* =========================================================
   A. DROP các procedure dư/bị lệch từ bản biến thể nâng cấp
   ========================================================= */
IF OBJECT_ID(N'dbo.ImportDetails_InsertLotVariantUnit', N'P') IS NOT NULL
    DROP PROCEDURE dbo.ImportDetails_InsertLotVariantUnit;
GO

IF OBJECT_ID(N'dbo.OrderItemLots_AllocateFEFO_VariantUnit', N'P') IS NOT NULL
    DROP PROCEDURE dbo.OrderItemLots_AllocateFEFO_VariantUnit;
GO

IF OBJECT_ID(N'dbo.OrderItems_InsertVariantUnit', N'P') IS NOT NULL
    DROP PROCEDURE dbo.OrderItems_InsertVariantUnit;
GO

IF OBJECT_ID(N'dbo.ProductLots_GetAvailableForSaleByVariantUnit', N'P') IS NOT NULL
    DROP PROCEDURE dbo.ProductLots_GetAvailableForSaleByVariantUnit;
GO

IF OBJECT_ID(N'dbo.ProductUnitConversion_Upsert', N'P') IS NOT NULL
    DROP PROCEDURE dbo.ProductUnitConversion_Upsert;
GO

IF OBJECT_ID(N'dbo.ProductVariant_Upsert', N'P') IS NOT NULL
    DROP PROCEDURE dbo.ProductVariant_Upsert;
GO

IF OBJECT_ID(N'dbo.fn_ProductUnitConversionToBase', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ProductUnitConversionToBase;
GO

/* =========================================================
   B. Thêm procedure C# hiện tại đang gọi nhưng SQL đang thiếu
   ========================================================= */
IF OBJECT_ID(N'dbo.CustomerPayments_GetDebt', N'P') IS NOT NULL
    DROP PROCEDURE dbo.CustomerPayments_GetDebt;
GO

CREATE PROCEDURE dbo.CustomerPayments_GetDebt
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
        FROM dbo.orders
        WHERE customer_id = @CustomerId
          AND ISNULL(status, '') <> N'Cancelled'
    ), 0);

    DECLARE @PaidDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.customer_payments
        WHERE customer_id = @CustomerId
    ), 0);

    SELECT (@OrderDebt - @PaidDebt) AS CurrentDebt;
END
GO

IF OBJECT_ID(N'dbo.OrderItems_Delete', N'P') IS NOT NULL
    DROP PROCEDURE dbo.OrderItems_Delete;
GO

CREATE PROCEDURE dbo.OrderItems_Delete
    @OrderItemId INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.order_items
    WHERE order_item_id = @OrderItemId;
END
GO

/* =========================================================
   C. OPTIONAL - chỉ chạy thủ công nếu chắc chắn bỏ hẳn biến thể
   =========================================================

-- Các bảng này thuộc nhánh biến thể/đơn vị quy đổi, C# hiện tại không gọi trực tiếp.
-- KHÔNG bật phần này nếu DB đang có dữ liệu biến thể cần giữ.

-- IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NOT NULL DROP TABLE dbo.product_variant_attributes;
-- IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NOT NULL DROP TABLE dbo.product_unit_conversions;
-- IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL DROP TABLE dbo.product_variants;

-- Các cột biến thể đang nằm trong order_items/import_details.
-- Chỉ xóa khi đã kiểm tra không có code/report nào dùng.

-- ALTER TABLE dbo.order_items DROP COLUMN product_variant_id, unit_id, input_quantity, base_quantity, unit_conversion_to_base, variant_name_snapshot, unit_name_snapshot;
-- ALTER TABLE dbo.import_details DROP COLUMN product_variant_id, unit_id, input_quantity, base_quantity, unit_conversion_to_base, variant_name_snapshot, unit_name_snapshot;
*/
