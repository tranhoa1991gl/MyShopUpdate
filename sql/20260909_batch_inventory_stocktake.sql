/*
MigrationId: 20260909_batch_inventory_stocktake
Purpose: Luu kiem ke theo tung lo / han su dung (batch/expiry date), tuong tu kiem ke bien the.
Safe: Chi bo sung cot batch_id, index, khoa ngoai va cap nhat thu tuc xem chi tiet phieu; khong sua so ton hay du lieu lich su.
*/

SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NULL
    THROW 51320, N'Không tìm thấy bảng inventory_check_details để cập nhật kiểm kê theo lô.', 1;

IF OBJECT_ID(N'dbo.product_batches', N'U') IS NULL
    THROW 51321, N'Không tìm thấy bảng product_batches để cập nhật kiểm kê theo lô.', 1;

IF COL_LENGTH(N'dbo.inventory_check_details', N'batch_id') IS NULL
    ALTER TABLE dbo.inventory_check_details ADD batch_id INT NULL;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.inventory_check_details')
      AND name = N'UX_inventory_check_details_check_product'
)
    DROP INDEX [UX_inventory_check_details_check_product] ON dbo.inventory_check_details;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.inventory_check_details')
      AND name = N'UX_inventory_check_details_check_product_variant'
)
    DROP INDEX [UX_inventory_check_details_check_product_variant] ON dbo.inventory_check_details;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.inventory_check_details')
      AND name = N'UX_inventory_check_details_check_product_variant_batch'
)
    DROP INDEX [UX_inventory_check_details_check_product_variant_batch] ON dbo.inventory_check_details;

CREATE UNIQUE NONCLUSTERED INDEX [UX_inventory_check_details_check_product_variant_batch]
ON dbo.inventory_check_details(check_id ASC, product_id ASC, variant_id ASC, batch_id ASC);

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.inventory_check_details')
      AND name = N'FK_inventory_check_details_batch'
)
BEGIN
    ALTER TABLE dbo.inventory_check_details WITH CHECK
        ADD CONSTRAINT [FK_inventory_check_details_batch]
        FOREIGN KEY([batch_id]) REFERENCES dbo.product_batches([batch_id]);
    ALTER TABLE dbo.inventory_check_details CHECK CONSTRAINT [FK_inventory_check_details_batch];
END

GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.InventoryCheck_GetDetails
    @CheckId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        id.detail_id AS DetailId,
        id.product_id AS ProductId,
        id.variant_id AS VariantId,
        id.batch_id AS BatchId,
        p.product_code AS ProductCode,
        p.product_name AS ProductName,
        ISNULL(pv.variant_name, N'') AS VariantName,
        ISNULL(pb.batch_code, N'') AS BatchCode,
        pb.expiry_date AS ExpiryDate,
        id.system_stock AS SystemStock,
        id.actual_stock AS ActualStock,
        id.difference AS Difference,
        id.reason AS Reason
    FROM dbo.inventory_check_details id
    INNER JOIN dbo.products p ON id.product_id = p.product_id
    LEFT JOIN dbo.product_variants pv ON id.variant_id = pv.variant_id
    LEFT JOIN dbo.product_batches pb ON id.batch_id = pb.batch_id
    WHERE id.check_id = @CheckId
    ORDER BY id.detail_id;
END
GO
