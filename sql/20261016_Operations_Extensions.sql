-- Additive extension: an empty configuration preserves existing business behavior.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @lock int;
EXEC @lock=sys.sp_getapplock @Resource=N'POS.OperationsExtensions.Schema',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
IF @lock<0 THROW 51000,N'Chưa thể chuẩn bị chức năng vận hành. Vui lòng thử lại.',1;
IF OBJECT_ID(N'dbo.pos_ext_notice_state',N'U') IS NULL
CREATE TABLE dbo.pos_ext_notice_state(user_id int NOT NULL,notice_key varchar(100) NOT NULL,notified_at datetime2 NULL,read_at datetime2 NULL,PRIMARY KEY(user_id,notice_key));
IF OBJECT_ID(N'dbo.pos_ext_period',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.pos_ext_period(id int PRIMARY KEY CHECK(id=1),closed_through date NULL,updated_by int NOT NULL,updated_at datetime2 NOT NULL,version rowversion);
 INSERT dbo.pos_ext_period(id,closed_through,updated_by,updated_at) VALUES(1,NULL,0,SYSDATETIME());
END;
IF NOT EXISTS(SELECT 1 FROM dbo.pos_ext_period WHERE id=1)
INSERT dbo.pos_ext_period(id,closed_through,updated_by,updated_at) VALUES(1,NULL,0,SYSDATETIME());
IF OBJECT_ID(N'dbo.pos_ext_contacts',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.pos_ext_contacts(contact_id bigint IDENTITY PRIMARY KEY,customer_id int NOT NULL REFERENCES dbo.customers(customer_id),owner_id int NOT NULL,
  subject nvarchar(200) NOT NULL,due_at datetime2 NOT NULL,completed_at datetime2 NULL,result nvarchar(1000) NOT NULL DEFAULT N'',created_at datetime2 NOT NULL DEFAULT SYSDATETIME(),version rowversion);
 CREATE INDEX IX_pos_ext_contacts_due ON dbo.pos_ext_contacts(owner_id,completed_at,due_at) INCLUDE(customer_id,subject);
END;
IF OBJECT_ID(N'dbo.pos_ext_promotions',N'U') IS NULL
CREATE TABLE dbo.pos_ext_promotions(promotion_id int IDENTITY PRIMARY KEY,name nvarchar(150) NOT NULL,starts_at datetime2 NOT NULL,ends_at datetime2 NOT NULL,
 product_id int NULL REFERENCES dbo.products(product_id),customer_group nvarchar(50) NOT NULL DEFAULT N'',minimum_quantity decimal(18,3) NOT NULL DEFAULT 1,
 minimum_total decimal(18,0) NOT NULL DEFAULT 0,discount_percent decimal(9,3) NOT NULL,enabled bit NOT NULL DEFAULT 0,version rowversion,
 CHECK(ends_at>starts_at AND minimum_quantity>0 AND minimum_total>=0 AND discount_percent>0 AND discount_percent<=100));
IF OBJECT_ID(N'dbo.pos_ext_receipts',N'U') IS NULL
CREATE TABLE dbo.pos_ext_receipts(receipt_token uniqueidentifier PRIMARY KEY,source_import_id int NOT NULL,receipt_import_id int NOT NULL UNIQUE,created_by int NOT NULL,created_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID(N'dbo.pos_ext_receipt_lines',N'U') IS NULL
CREATE TABLE dbo.pos_ext_receipt_lines(receipt_token uniqueidentifier NOT NULL REFERENCES dbo.pos_ext_receipts(receipt_token),source_detail_id int NOT NULL,quantity decimal(18,3) NOT NULL CHECK(quantity>0),PRIMARY KEY(receipt_token,source_detail_id));
IF OBJECT_ID(N'dbo.pos_ext_exchanges',N'U') IS NULL
CREATE TABLE dbo.pos_ext_exchanges(exchange_token uniqueidentifier PRIMARY KEY,original_order_id int NOT NULL,return_order_id int NOT NULL UNIQUE,new_order_id int NOT NULL UNIQUE,created_by int NOT NULL,created_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID(N'dbo.pos_ext_cart_commits',N'U') IS NULL
CREATE TABLE dbo.pos_ext_cart_commits(cart_token uniqueidentifier PRIMARY KEY,document_kind varchar(10) NOT NULL,document_id int NOT NULL,user_id int NOT NULL,committed_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF NOT EXISTS(SELECT 1 FROM dbo.pos_ops_settings WHERE setting_key=N'CartEpoch')
INSERT dbo.pos_ops_settings(setting_key,setting_value) VALUES(N'CartEpoch',CONVERT(nvarchar(36),NEWID()));
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.pos_ext_receipt_lines') AND name=N'IX_pos_ext_receipt_lines_source')
CREATE INDEX IX_pos_ext_receipt_lines_source ON dbo.pos_ext_receipt_lines(source_detail_id) INCLUDE(quantity);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.pos_ext_receipts') AND name=N'IX_pos_ext_receipts_source')
CREATE INDEX IX_pos_ext_receipts_source ON dbo.pos_ext_receipts(source_import_id) INCLUDE(receipt_import_id,created_at);
-- New ancillary settings must not prevent the existing deletion of unused records.
DECLARE @ExtFk sysname,@ExtTable sysname,@ExtDrop nvarchar(max);
WHILE EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id IN(OBJECT_ID(N'dbo.pos_ext_contacts'),OBJECT_ID(N'dbo.pos_ext_promotions')) AND delete_referential_action=0)
BEGIN
 SELECT TOP(1) @ExtFk=name,@ExtTable=OBJECT_NAME(parent_object_id) FROM sys.foreign_keys
 WHERE parent_object_id IN(OBJECT_ID(N'dbo.pos_ext_contacts'),OBJECT_ID(N'dbo.pos_ext_promotions')) AND delete_referential_action=0;
 SET @ExtDrop=N'ALTER TABLE dbo.'+QUOTENAME(@ExtTable)+N' DROP CONSTRAINT '+QUOTENAME(@ExtFk);EXEC sys.sp_executesql @ExtDrop;
 IF @ExtTable=N'pos_ext_contacts' ALTER TABLE dbo.pos_ext_contacts ADD CONSTRAINT FK_pos_ext_contacts_customer FOREIGN KEY(customer_id) REFERENCES dbo.customers(customer_id) ON DELETE CASCADE;
 ELSE ALTER TABLE dbo.pos_ext_promotions ADD CONSTRAINT FK_pos_ext_promotions_product FOREIGN KEY(product_id) REFERENCES dbo.products(product_id) ON DELETE CASCADE;
END;
-- Period write guards are inactive until an administrator closes a date.
IF OBJECT_ID(N'dbo.orders',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_orders',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_orders ON dbo.orders AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_orders ON dbo.orders AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON i.order_id=d.order_id WHERE (i.order_date<DATEADD(day,1,@Closed) OR d.order_date<DATEADD(day,1,@Closed)) AND (i.order_id IS NULL OR d.order_id IS NULL OR EXISTS(SELECT i.customer_id,i.employee_id,i.order_date,i.total_amount,i.discount,i.vat_amount,i.final_amount,i.paid_amount,i.payment_method,i.order_type,i.original_order_id,i.points_earned,i.points_used EXCEPT SELECT d.customer_id,d.employee_id,d.order_date,d.total_amount,d.discount,d.vat_amount,d.final_amount,d.paid_amount,d.payment_method,d.order_type,d.original_order_id,d.points_earned,d.points_used) OR (ISNULL(i.status,'''')<>ISNULL(d.status,'''') AND (i.status IN(''Cancelled'',''Canceled'',''Pending'') OR d.status IN(''Cancelled'',''Canceled'',''Pending''))))) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.imports',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_imports',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_imports ON dbo.imports AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_imports ON dbo.imports AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON i.import_id=d.import_id WHERE (i.import_date<DATEADD(day,1,@Closed) OR d.import_date<DATEADD(day,1,@Closed)) AND (i.import_id IS NULL OR d.import_id IS NULL OR EXISTS(SELECT i.supplier_id,i.employee_id,i.import_date,i.total_amount,i.discount,i.vat_amount,i.final_amount,i.paid_amount,i.supplier_credit_applied,i.supplier_refund_received,i.payment_method EXCEPT SELECT d.supplier_id,d.employee_id,d.import_date,d.total_amount,d.discount,d.vat_amount,d.final_amount,d.paid_amount,d.supplier_credit_applied,d.supplier_refund_received,d.payment_method) OR (ISNULL(i.status,'''')<>ISNULL(d.status,'''') AND (i.status IN(''Cancelled'',''Canceled'',''Pending'') OR d.status IN(''Cancelled'',''Canceled'',''Pending''))))) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.order_items',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_order_items',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_order_items ON dbo.order_items AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_order_items ON dbo.order_items AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON i.order_item_id=d.order_item_id WHERE EXISTS(SELECT 1 FROM dbo.orders p WHERE p.order_id IN(i.order_id,d.order_id) AND p.order_date<DATEADD(day,1,@Closed)) AND (i.order_item_id IS NULL OR d.order_item_id IS NULL OR EXISTS(SELECT i.order_id,i.product_id,i.quantity,i.unit_price,i.cost_price,i.product_variant_id,i.unit_id,i.base_quantity,i.unit_conversion_to_base,i.gift_quantity,i.serial_number EXCEPT SELECT d.order_id,d.product_id,d.quantity,d.unit_price,d.cost_price,d.product_variant_id,d.unit_id,d.base_quantity,d.unit_conversion_to_base,d.gift_quantity,d.serial_number))) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.import_details',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_import_details',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_import_details ON dbo.import_details AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_import_details ON dbo.import_details AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted i FULL JOIN deleted d ON i.import_detail_id=d.import_detail_id WHERE EXISTS(SELECT 1 FROM dbo.imports p WHERE p.import_id IN(i.import_id,d.import_id) AND p.import_date<DATEADD(day,1,@Closed)) AND (i.import_detail_id IS NULL OR d.import_detail_id IS NULL OR EXISTS(SELECT i.import_id,i.product_id,i.quantity,i.import_price,i.total,i.variant_id,i.unit_id,i.base_quantity,i.unit_conversion_to_base EXCEPT SELECT d.import_id,d.product_id,d.quantity,d.import_price,d.total,d.variant_id,d.unit_id,d.base_quantity,d.unit_conversion_to_base))) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.cashbook_entries',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_cashbook_entries',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_cashbook_entries ON dbo.cashbook_entries AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_cashbook_entries ON dbo.cashbook_entries AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted WHERE entry_date<DATEADD(day,1,@Closed)) OR EXISTS(SELECT 1 FROM deleted WHERE entry_date<DATEADD(day,1,@Closed)) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.customer_payments',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_customer_payments',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_customer_payments ON dbo.customer_payments AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_customer_payments ON dbo.customer_payments AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted WHERE payment_date<DATEADD(day,1,@Closed)) OR EXISTS(SELECT 1 FROM deleted WHERE payment_date<DATEADD(day,1,@Closed)) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.supplier_payments',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_supplier_payments',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_supplier_payments ON dbo.supplier_payments AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_supplier_payments ON dbo.supplier_payments AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted WHERE payment_date<DATEADD(day,1,@Closed)) OR EXISTS(SELECT 1 FROM deleted WHERE payment_date<DATEADD(day,1,@Closed)) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
IF OBJECT_ID(N'dbo.purchase_returns',N'U') IS NOT NULL
BEGIN
IF OBJECT_ID(N'dbo.TR_pos_ext_period_purchase_returns',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.TR_pos_ext_period_purchase_returns ON dbo.purchase_returns AFTER INSERT AS BEGIN SET NOCOUNT ON; END');
EXEC(N'ALTER TRIGGER dbo.TR_pos_ext_period_purchase_returns ON dbo.purchase_returns AFTER INSERT,UPDATE,DELETE AS
BEGIN
SET NOCOUNT ON;
DECLARE @Closed date=(SELECT closed_through FROM dbo.pos_ext_period WITH(HOLDLOCK) WHERE id=1);
IF @Closed IS NULL RETURN;
IF EXISTS(SELECT 1 FROM inserted WHERE return_date<DATEADD(day,1,@Closed)) OR EXISTS(SELECT 1 FROM deleted WHERE return_date<DATEADD(day,1,@Closed)) THROW 51001,N''Chứng từ thuộc kỳ đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.'',1;
END;');
END;
COMMIT;
