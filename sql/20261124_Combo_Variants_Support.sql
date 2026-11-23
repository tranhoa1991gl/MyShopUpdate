SET XACT_ABORT ON;
DECLARE @own bit = CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
IF @own=1 BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @lock int;
    EXEC @lock=sys.sp_getapplock @Resource=N'HoaTranPOS.ComboVariants.20261124',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=30000;
    IF @lock<0 THROW 51240,N'Chưa thể khóa cấu hình biến thể Combo.',1;

    IF OBJECT_ID(N'dbo.product_combo_variant_items',N'U') IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id=OBJECT_ID(N'dbo.product_variants')
            AND i.is_unique=1 AND i.has_filter=0 AND i.is_disabled=0
            AND INDEX_COL(N'dbo.product_variants',i.index_id,1)=N'variant_id'
            AND INDEX_COL(N'dbo.product_variants',i.index_id,2)=N'product_id'
            AND INDEX_COL(N'dbo.product_variants',i.index_id,3) IS NULL)
            CREATE UNIQUE INDEX UX_pcvi_variant_product ON dbo.product_variants(variant_id,product_id);
        CREATE TABLE dbo.product_combo_variant_items (
            combo_variant_item_id int IDENTITY PRIMARY KEY,
            combo_product_id int NOT NULL,
            combo_variant_id int NOT NULL,
            component_product_id int NOT NULL REFERENCES dbo.products(product_id),
            component_variant_id int NULL,
            quantity decimal(18,3) NOT NULL CHECK(quantity>0),
            note nvarchar(255) NULL,
            created_at datetime NOT NULL DEFAULT GETDATE(),
            CHECK(component_product_id<>combo_product_id),
            FOREIGN KEY(combo_variant_id,combo_product_id) REFERENCES dbo.product_variants(variant_id,product_id) ON DELETE CASCADE,
            FOREIGN KEY(component_variant_id,component_product_id) REFERENCES dbo.product_variants(variant_id,product_id),
            UNIQUE(combo_product_id,combo_variant_id,component_product_id,component_variant_id)
        );
        CREATE INDEX IX_pcvi_component ON dbo.product_combo_variant_items(component_product_id,combo_product_id);
    END;
    IF COL_LENGTH(N'dbo.order_item_combo_snapshots',N'combo_variant_id') IS NULL
        ALTER TABLE dbo.order_item_combo_snapshots ADD combo_variant_id int NULL;
    IF COL_LENGTH(N'dbo.order_item_combo_snapshots',N'combo_variant_name') IS NULL
        ALTER TABLE dbo.order_item_combo_snapshots ADD combo_variant_name nvarchar(150) NULL;
    IF @own=1 COMMIT;
END TRY
BEGIN CATCH
    IF @own=1 AND XACT_STATE()<>0 ROLLBACK;
    THROW;
END CATCH;
