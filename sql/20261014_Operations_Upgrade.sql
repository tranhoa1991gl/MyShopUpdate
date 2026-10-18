-- Additive, opt-in operations module. No existing business row is rewritten.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF OBJECT_ID(N'dbo.pos_ops_settings',N'U') IS NULL
CREATE TABLE dbo.pos_ops_settings(setting_key nvarchar(80) NOT NULL PRIMARY KEY,setting_value nvarchar(2000) NOT NULL,updated_at datetime2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID(N'dbo.pos_ops_stock_policy',N'U') IS NULL
CREATE TABLE dbo.pos_ops_stock_policy(
 product_id int NOT NULL PRIMARY KEY REFERENCES dbo.products(product_id) ON DELETE CASCADE,minimum_stock decimal(18,3) NOT NULL,
 target_stock decimal(18,3) NOT NULL,order_multiple decimal(18,3) NOT NULL DEFAULT 1,
 supplier_id int NULL REFERENCES dbo.suppliers(supplier_id) ON DELETE SET NULL,enabled bit NOT NULL DEFAULT 1,
 updated_by int NOT NULL,updated_at datetime2 NOT NULL DEFAULT SYSDATETIME(),version rowversion,
 CONSTRAINT CK_pos_ops_stock_policy CHECK(minimum_stock>=0 AND target_stock>=minimum_stock AND order_multiple>0));
IF OBJECT_ID(N'dbo.pos_ops_debt_terms',N'U') IS NULL
CREATE TABLE dbo.pos_ops_debt_terms(
 source_kind varchar(12) NOT NULL,source_id int NOT NULL,partner_id int NOT NULL,due_date date NULL,
 promised_date date NULL,note nvarchar(1000) NOT NULL DEFAULT N'',updated_by int NOT NULL,
 updated_at datetime2 NOT NULL DEFAULT SYSDATETIME(),version rowversion,
 PRIMARY KEY(source_kind,source_id),CONSTRAINT CK_pos_ops_debt_kind CHECK(source_kind IN('ORDER','REPAIR','IMPORT','ADJUSTMENT')));
IF OBJECT_ID(N'dbo.pos_ops_debt_contacts',N'U') IS NULL
CREATE TABLE dbo.pos_ops_debt_contacts(
 contact_id bigint IDENTITY PRIMARY KEY,source_kind varchar(12) NOT NULL,source_id int NOT NULL,
 partner_id int NOT NULL,contacted_at datetime2 NOT NULL DEFAULT SYSDATETIME(),contact_method nvarchar(50) NOT NULL,
 result nvarchar(1000) NOT NULL,promised_date date NULL,created_by int NOT NULL,created_name nvarchar(100) NOT NULL);
IF OBJECT_ID(N'dbo.pos_ops_approvals',N'U') IS NULL
CREATE TABLE dbo.pos_ops_approvals(
 request_id bigint IDENTITY PRIMARY KEY,request_token uniqueidentifier NOT NULL UNIQUE,request_kind varchar(20) NOT NULL,
 source_id int NOT NULL,reference_code nvarchar(60) NOT NULL,requested_value decimal(18,3) NOT NULL,
 snapshot nvarchar(max) NOT NULL,reason nvarchar(1000) NOT NULL,requested_by int NOT NULL,requested_name nvarchar(100) NOT NULL,
 requested_at datetime2 NOT NULL DEFAULT SYSDATETIME(),expires_at datetime2 NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'Pending',reviewed_by int NULL,reviewed_name nvarchar(100) NULL,
 reviewed_at datetime2 NULL,review_note nvarchar(1000) NULL,completed_at datetime2 NULL,result_reference nvarchar(100) NULL,
 version rowversion,CONSTRAINT CK_pos_ops_approval_kind CHECK(request_kind IN('DISCOUNT','CANCEL_ORDER','STOCK')),
 CONSTRAINT CK_pos_ops_approval_status CHECK(status IN('Pending','Approved','Rejected','Cancelled','Completed')));
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.pos_ops_approvals') AND name=N'IX_pos_ops_approvals_queue')
CREATE INDEX IX_pos_ops_approvals_queue ON dbo.pos_ops_approvals(status,requested_at) INCLUDE(requested_by,expires_at);
IF OBJECT_ID(N'dbo.pos_ops_audit',N'U') IS NULL
CREATE TABLE dbo.pos_ops_audit(
 audit_id bigint IDENTITY PRIMARY KEY,occurred_at datetime2 NOT NULL DEFAULT SYSDATETIME(),entity_name nvarchar(80) NOT NULL,
 entity_id nvarchar(100) NOT NULL,action_name nvarchar(30) NOT NULL,actor_id int NULL,actor_name nvarchar(100) NULL,
 host_name nvarchar(128) NULL,sql_login nvarchar(128) NULL,before_data nvarchar(max) NULL,after_data nvarchar(max) NULL,
 reason nvarchar(1000) NULL);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.pos_ops_audit') AND name=N'IX_pos_ops_audit_date')
CREATE INDEX IX_pos_ops_audit_date ON dbo.pos_ops_audit(occurred_at DESC) INCLUDE(entity_name,entity_id,actor_id);
IF OBJECT_ID(N'dbo.pos_ops_backup_runs',N'U') IS NULL
CREATE TABLE dbo.pos_ops_backup_runs(
 run_id bigint IDENTITY PRIMARY KEY,started_at datetime2 NOT NULL DEFAULT SYSDATETIME(),finished_at datetime2 NULL,
 machine_name nvarchar(128) NOT NULL,run_token uniqueidentifier NOT NULL UNIQUE,created_by int NOT NULL,status varchar(20) NOT NULL,package_path nvarchar(2000) NULL,
 secondary_path nvarchar(2000) NULL,restore_verified bit NOT NULL DEFAULT 0,message nvarchar(2000) NULL,
 CONSTRAINT CK_pos_ops_backup_status CHECK(status IN('Running','Success','Failed')));
IF OBJECT_ID(N'dbo.pos_ops_drafts',N'U') IS NULL
CREATE TABLE dbo.pos_ops_drafts(draft_token uniqueidentifier NOT NULL PRIMARY KEY,import_id int NOT NULL,created_at datetime2 NOT NULL DEFAULT SYSDATETIME(),created_by int NOT NULL);
-- Metadata must not prevent the existing removal of unused products, suppliers or draft imports.
DECLARE @OpsConstraint sysname,@OpsDrop nvarchar(max);
WHILE EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.pos_ops_drafts') AND referenced_object_id=OBJECT_ID(N'dbo.imports'))
BEGIN
 SELECT TOP(1) @OpsConstraint=name FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.pos_ops_drafts') AND referenced_object_id=OBJECT_ID(N'dbo.imports');
 SET @OpsDrop=N'ALTER TABLE dbo.pos_ops_drafts DROP CONSTRAINT '+QUOTENAME(@OpsConstraint);EXEC sys.sp_executesql @OpsDrop;
END;
WHILE EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.pos_ops_stock_policy') AND referenced_object_id IN(OBJECT_ID(N'dbo.products'),OBJECT_ID(N'dbo.suppliers')) AND delete_referential_action=0)
BEGIN
 DECLARE @OpsReferenced int;
 SELECT TOP(1) @OpsConstraint=name,@OpsReferenced=referenced_object_id FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.pos_ops_stock_policy') AND referenced_object_id IN(OBJECT_ID(N'dbo.products'),OBJECT_ID(N'dbo.suppliers')) AND delete_referential_action=0;
 SET @OpsDrop=N'ALTER TABLE dbo.pos_ops_stock_policy DROP CONSTRAINT '+QUOTENAME(@OpsConstraint);EXEC sys.sp_executesql @OpsDrop;
 IF @OpsReferenced=OBJECT_ID(N'dbo.products') ALTER TABLE dbo.pos_ops_stock_policy ADD CONSTRAINT FK_pos_ops_policy_product FOREIGN KEY(product_id) REFERENCES dbo.products(product_id) ON DELETE CASCADE;
 ELSE ALTER TABLE dbo.pos_ops_stock_policy ADD CONSTRAINT FK_pos_ops_policy_supplier FOREIGN KEY(supplier_id) REFERENCES dbo.suppliers(supplier_id) ON DELETE SET NULL;
END;
IF NOT EXISTS(SELECT 1 FROM dbo.pos_ops_settings WHERE setting_key=N'AuditEnabled')
INSERT dbo.pos_ops_settings(setting_key,setting_value) VALUES(N'AuditEnabled',N'0');
COMMIT;
