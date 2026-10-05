-- Additive only: no customer data is replaced and no historical dates are invented.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @LockResult int;
EXEC @LockResult=sys.sp_getapplock @Resource=N'HoaTranPOS.DeliveryStockSchema.20261004',
    @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=30000;
IF @LockResult<0 THROW 51200,N'Chưa thể nâng cấp giữ hàng. Vui lòng thử lại.',1;
IF COL_LENGTH(N'dbo.orders',N'is_delivery') IS NULL
    ALTER TABLE dbo.orders ADD is_delivery bit NOT NULL CONSTRAINT DF_stock_integrity_delivery DEFAULT(0);
IF COL_LENGTH(N'dbo.orders',N'delivery_status') IS NULL
    ALTER TABLE dbo.orders ADD delivery_status nvarchar(30) NULL;

IF COL_LENGTH(N'dbo.orders',N'cancelled_at') IS NULL
    ALTER TABLE dbo.orders ADD cancelled_at datetime NULL;
IF COL_LENGTH(N'dbo.orders',N'stock_posted_at') IS NULL
    ALTER TABLE dbo.orders ADD stock_posted_at datetime NULL;
IF COL_LENGTH(N'dbo.orders',N'delivery_reservation_initialized') IS NULL
    ALTER TABLE dbo.orders ADD delivery_reservation_initialized bit NULL;

IF OBJECT_ID(N'dbo.order_delivery_reservations',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.order_delivery_reservations
    (
        reservation_id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        order_id int NOT NULL, order_item_id int NOT NULL,
        product_id int NOT NULL, variant_id int NULL, batch_id int NULL,
        reserved_base_qty decimal(18,3) NOT NULL,
        created_at datetime NOT NULL CONSTRAINT DF_delivery_reservation_created DEFAULT(GETDATE()),
        CONSTRAINT CK_delivery_reservation_qty CHECK(reserved_base_qty>0)
    );
    CREATE INDEX IX_delivery_reservation_order ON dbo.order_delivery_reservations(order_id);
    CREATE INDEX IX_delivery_reservation_stock ON dbo.order_delivery_reservations(product_id,variant_id,batch_id)
        INCLUDE(order_id,reserved_base_qty);
END;

-- Independent snapshots survive deletion of a cancelled invoice.
IF OBJECT_ID(N'dbo.order_stock_movements',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.order_stock_movements
    (
        movement_id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        order_id int NOT NULL, order_item_id int NOT NULL, product_id int NOT NULL, variant_id int NULL,
        movement_type nvarchar(20) NOT NULL, quantity_change decimal(18,3) NOT NULL,
        movement_date datetime NOT NULL, order_code nvarchar(100) NULL,
        partner_name nvarchar(250) NULL, note nvarchar(1000) NULL,
        CONSTRAINT CK_order_movement_qty CHECK(quantity_change<>0)
    );
    CREATE UNIQUE INDEX UX_order_stock_movement ON dbo.order_stock_movements
        (order_id,order_item_id,product_id,variant_id,movement_type);
    CREATE INDEX IX_order_stock_movement_period ON dbo.order_stock_movements(product_id,movement_date)
        INCLUDE(quantity_change,order_id);
END;

IF COL_LENGTH(N'dbo.order_stock_movements',N'movement_value') IS NULL
    ALTER TABLE dbo.order_stock_movements ADD movement_value decimal(18,0) NOT NULL
        CONSTRAINT DF_order_movement_value DEFAULT(0);

-- Protect reservations even when another stock consumer is used (export,
-- manufacturing, repairs, inventory edits, or cancellation of an import).
-- Negative ordinary stock retains the shop's explicitly enabled policy.
IF OBJECT_ID(N'dbo.TR_products_delivery_reservation',N'TR') IS NULL
EXEC(N'CREATE TRIGGER dbo.TR_products_delivery_reservation ON dbo.products AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.product_id=d.product_id
   CROSS APPLY(SELECT SUM(r.reserved_base_qty) qty FROM dbo.order_delivery_reservations r WHERE r.product_id=d.product_id) held
   WHERE held.qty>0 AND (i.product_id IS NULL OR
       (ISNULL(i.stock,0)<ISNULL(d.stock,0) AND ISNULL(i.stock,0)<held.qty
        AND (ISNULL(i.has_batch_expiry,0)=1 OR ISNULL((SELECT TOP(1) allow_negative_stock FROM dbo.StoreInfo),0)=0))))
   THROW 51201,N''Hàng đang được giữ cho đơn giao. Tồn khả dụng không đủ; vui lòng giảm số lượng hoặc xử lý đơn giao trước.'',1;
END');

IF OBJECT_ID(N'dbo.TR_variants_delivery_reservation',N'TR') IS NULL
EXEC(N'CREATE TRIGGER dbo.TR_variants_delivery_reservation ON dbo.product_variants AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.variant_id=d.variant_id
   JOIN dbo.products p ON p.product_id=d.product_id
   CROSS APPLY(SELECT SUM(r.reserved_base_qty) qty FROM dbo.order_delivery_reservations r WHERE r.variant_id=d.variant_id) held
   WHERE held.qty>0 AND (i.variant_id IS NULL OR
       (ISNULL(i.stock_base_qty,0)<ISNULL(d.stock_base_qty,0) AND ISNULL(i.stock_base_qty,0)<held.qty
        AND (ISNULL(p.has_batch_expiry,0)=1 OR ISNULL((SELECT TOP(1) allow_negative_stock FROM dbo.StoreInfo),0)=0))))
   THROW 51202,N''Biến thể đang được giữ cho đơn giao. Tồn khả dụng không đủ.'',1;
END');

IF OBJECT_ID(N'dbo.TR_batches_delivery_reservation',N'TR') IS NULL
EXEC(N'CREATE TRIGGER dbo.TR_batches_delivery_reservation ON dbo.product_batches AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.batch_id=d.batch_id
   CROSS APPLY(SELECT SUM(r.reserved_base_qty) qty FROM dbo.order_delivery_reservations r WHERE r.batch_id=d.batch_id) held
   WHERE held.qty>0 AND (i.batch_id IS NULL OR i.is_cancelled=1 OR i.is_posted=0 OR i.quantity_remaining<held.qty))
   THROW 51203,N''Lô hàng đang được giữ cho đơn giao. Không thể xuất hoặc hủy phần đã giữ.'',1;
END');
COMMIT TRANSACTION;
