-- Additive and repeatable. Existing invoices deliberately keep NULL line points.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @LockResult INT;
EXEC @LockResult=sys.sp_getapplock @Resource=N'HoaTranPOS.ProductLoyalty.Schema',
 @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=15000;
IF @LockResult<0 THROW 51400,N'Không thể chuẩn bị dữ liệu tích điểm.',1;
IF OBJECT_ID(N'dbo.loyalty_point_settings',N'U') IS NULL
 CREATE TABLE dbo.loyalty_point_settings(
  id INT NOT NULL PRIMARY KEY CHECK(id=1),
  is_enabled BIT NOT NULL DEFAULT(0),
  fallback_mode VARCHAR(12) NOT NULL DEFAULT('DEFAULT_RATE') CHECK(fallback_mode IN('DEFAULT_RATE','NONE')),
  revision BIGINT NOT NULL DEFAULT(0),
  updated_by INT NULL,updated_at DATETIME2 NOT NULL DEFAULT(SYSDATETIME())
 );
IF NOT EXISTS(SELECT 1 FROM dbo.loyalty_point_settings WHERE id=1)
 INSERT dbo.loyalty_point_settings(id) VALUES(1);
IF OBJECT_ID(N'dbo.loyalty_point_rules',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.loyalty_point_rules(
  rule_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  target_type VARCHAR(10) NOT NULL CHECK(target_type IN('PRODUCT','CATEGORY')),
  target_id INT NOT NULL CHECK(target_id>0),
  rule_mode VARCHAR(8) NOT NULL CHECK(rule_mode IN('FIXED','RATE','NONE')),
  points_per_unit DECIMAL(18,6) NOT NULL DEFAULT(0) CHECK(points_per_unit BETWEEN 0 AND 1000000),
  money_per_point DECIMAL(18,2) NOT NULL DEFAULT(0) CHECK(money_per_point>=0),
  is_active BIT NOT NULL DEFAULT(1),
  updated_by INT NULL,updated_at DATETIME2 NOT NULL DEFAULT(SYSDATETIME()),
  CONSTRAINT UQ_loyalty_point_rules_target UNIQUE(target_type,target_id),
  CONSTRAINT CK_loyalty_point_rules_rate CHECK(rule_mode<>'RATE' OR money_per_point>0)
 );
END;
IF COL_LENGTH(N'dbo.order_items',N'points_earned') IS NULL
 ALTER TABLE dbo.order_items ADD points_earned INT NULL;
IF COL_LENGTH(N'dbo.order_items',N'loyalty_rule_snapshot') IS NULL
 ALTER TABLE dbo.order_items ADD loyalty_rule_snapshot NVARCHAR(160) NULL;
-- A negative line snapshot on a RETURN records earned points revoked by that return.
-- orders.points_earned / orders.points_used retain their existing refund semantics.
COMMIT TRANSACTION;
