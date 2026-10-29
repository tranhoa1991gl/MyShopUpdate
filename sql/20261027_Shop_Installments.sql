-- Shop-managed installments: complete migration (consolidated before public release).
-- Order: Base -> LateFees -> SettlementPolicy -> Menu.
-- Run this entire file against the shop database after backup. Safe to run repeatedly.
-- Section markers are also used by the application to load individual migration steps.

-- BEGIN INSTALLMENT SECTION: Base
-- Shop-managed installments. Monthly declining balance; no changes to old invoices.
-- Run against the shop database after backup. Safe to execute more than once.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @InstallmentLock INT;
EXEC @InstallmentLock=sys.sp_getapplock @Resource=N'HoaTranPOS.Installments.Schema',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=15000;
IF @InstallmentLock<0 THROW 51300,N'Không lấy được khóa chuẩn bị dữ liệu trả góp.',1;
IF OBJECT_ID(N'dbo.pos_installment_contracts',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.pos_installment_contracts(
  contract_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  request_token UNIQUEIDENTIFIER NOT NULL UNIQUE,
  contract_code NVARCHAR(40) NOT NULL UNIQUE,
  order_id INT NOT NULL REFERENCES dbo.orders(order_id),
  customer_id INT NOT NULL REFERENCES dbo.customers(customer_id),
  principal_amount DECIMAL(18,0) NOT NULL CHECK(principal_amount>0),
  term_months INT NOT NULL CHECK(term_months BETWEEN 1 AND 1200),
  annual_rate DECIMAL(12,6) NOT NULL CHECK(annual_rate BETWEEN 0 AND 100),
  start_date DATE NOT NULL,first_due_date DATE NOT NULL,
  status VARCHAR(12) NOT NULL DEFAULT('ACTIVE') CHECK(status IN('ACTIVE','SETTLED','CANCELLED')),
  note NVARCHAR(1000) NOT NULL DEFAULT(N''),
  created_by INT NOT NULL,created_at DATETIME2 NOT NULL DEFAULT(SYSDATETIME()),
  version ROWVERSION NOT NULL,
  CHECK(first_due_date>start_date AND first_due_date<=DATEADD(month,2,start_date)),
  CHECK(principal_amount>=term_months)
 );
 CREATE UNIQUE INDEX UX_pos_installment_order ON dbo.pos_installment_contracts(order_id) WHERE status<>'CANCELLED';
 CREATE INDEX IX_pos_installment_customer ON dbo.pos_installment_contracts(customer_id,status);
END;
IF OBJECT_ID(N'dbo.pos_installment_receipts',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.pos_installment_receipts(
  receipt_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  request_token UNIQUEIDENTIFIER NOT NULL UNIQUE,
  contract_id INT NOT NULL REFERENCES dbo.pos_installment_contracts(contract_id),
  -- Original receipts remain recorded; a void is matched by a refund entry.
  payment_id INT NOT NULL UNIQUE,
  paid_at DATETIME NOT NULL,
  amount DECIMAL(18,0) NOT NULL CHECK(amount>0),
  principal_amount DECIMAL(18,0) NOT NULL CHECK(principal_amount>=0),
  interest_amount DECIMAL(18,0) NOT NULL CHECK(interest_amount>=0),
  payment_method NVARCHAR(50) NOT NULL,
  account_id INT NULL,bank_code NVARCHAR(50) NULL,account_number NVARCHAR(50) NULL,account_owner NVARCHAR(200) NULL,
  payment_code NVARCHAR(100) NULL,bank_reference NVARCHAR(1000) NULL,
  created_by INT NOT NULL,created_at DATETIME2 NOT NULL DEFAULT(SYSDATETIME()),
  note NVARCHAR(1000) NOT NULL DEFAULT(N''),
  is_void BIT NOT NULL DEFAULT(0),voided_by INT NULL,voided_at DATETIME2 NULL,void_reason NVARCHAR(1000) NULL,refund_reference NVARCHAR(1000) NULL,
  CHECK(amount=principal_amount+interest_amount)
 );
 CREATE UNIQUE INDEX UX_pos_installment_qr ON dbo.pos_installment_receipts(payment_code) WHERE payment_code IS NOT NULL;
 CREATE INDEX IX_pos_installment_receipts_contract ON dbo.pos_installment_receipts(contract_id,is_void,paid_at,receipt_id)
 INCLUDE(principal_amount,interest_amount);
END;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'refund_reference') IS NULL
 ALTER TABLE dbo.pos_installment_receipts ADD refund_reference NVARCHAR(1000) NULL;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'refund_key') IS NULL
 ALTER TABLE dbo.pos_installment_receipts ADD refund_key CHAR(64) NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.pos_installment_receipts') AND name=N'UX_pos_installment_refund')
 EXEC(N'CREATE UNIQUE INDEX UX_pos_installment_refund ON dbo.pos_installment_receipts(refund_key) WHERE refund_key IS NOT NULL;');
IF OBJECT_ID(N'dbo.pos_installment_audit',N'U') IS NULL
 CREATE TABLE dbo.pos_installment_audit(
  audit_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  contract_id INT NOT NULL REFERENCES dbo.pos_installment_contracts(contract_id),
  action_name VARCHAR(30) NOT NULL,receipt_id INT NULL,
  actor_id INT NOT NULL,created_at DATETIME2 NOT NULL DEFAULT(SYSDATETIME()),
  detail NVARCHAR(2000) NOT NULL
 );
-- Preserve original money movements; voiding posts a refund, never deletes money.
IF OBJECT_ID(N'dbo.TR_InstallmentProtectCustomerPayment',N'TR') IS NOT NULL
 DROP TRIGGER dbo.TR_InstallmentProtectCustomerPayment;
 EXEC(N'CREATE TRIGGER dbo.TR_InstallmentProtectCustomerPayment ON dbo.customer_payments AFTER UPDATE,DELETE AS
 BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM deleted d JOIN dbo.pos_installment_receipts r ON r.payment_id=d.payment_id
   LEFT JOIN inserted i ON i.payment_id=d.payment_id WHERE i.payment_id IS NULL OR
    EXISTS(SELECT d.customer_id,d.amount,d.payment_date,d.employee_id,d.payment_method EXCEPT SELECT i.customer_id,i.amount,i.payment_date,i.employee_id,i.payment_method))
   THROW 51301,N''Phiếu thu thuộc hợp đồng trả góp. Hãy xử lý tại chức năng Trả góp.'',1;
 END;');
IF OBJECT_ID(N'dbo.TR_InstallmentProtectOrder',N'TR') IS NULL
 EXEC(N'CREATE TRIGGER dbo.TR_InstallmentProtectOrder ON dbo.orders AFTER UPDATE AS
 BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM deleted d JOIN inserted i ON i.order_id=d.order_id
   JOIN dbo.pos_installment_contracts c ON c.order_id=d.order_id AND c.status<>''CANCELLED''
   WHERE i.status IN(N''Pending'',N''Cancelled'',N''Canceled'',N''Đã hủy'',N''Hủy'')
    OR EXISTS(SELECT d.customer_id,d.total_amount,d.final_amount,d.paid_amount,d.discount,d.vat_amount,d.order_type,d.order_date
              EXCEPT SELECT i.customer_id,i.total_amount,i.final_amount,i.paid_amount,i.discount,i.vat_amount,i.order_type,i.order_date))
   THROW 51302,N''Không sửa tiền/khách/ngày hoặc hủy hóa đơn đã lập hợp đồng trả góp.'',1;
 END;');
IF OBJECT_ID(N'dbo.TR_InstallmentProtectReturn',N'TR') IS NULL
 EXEC(N'CREATE TRIGGER dbo.TR_InstallmentProtectReturn ON dbo.orders AFTER INSERT AS
 BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.pos_installment_contracts c ON c.order_id=i.original_order_id AND c.status<>''CANCELLED'' WHERE i.order_type=N''RETURN'')
   THROW 51303,N''Hóa đơn gốc có hợp đồng trả góp, cần đối chiếu hợp đồng trước khi trả hàng.'',1;
 END;');
COMMIT TRANSACTION;
-- END INSTALLMENT SECTION: Base

-- BEGIN INSTALLMENT SECTION: LateFees
-- Optional fixed daily late fee. Requires the Base section above.
-- Existing contracts/receipts keep zero fees. Safe to run repeatedly.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @LateFeesLock INT;
EXEC @LateFeesLock=sys.sp_getapplock @Resource=N'HoaTranPOS.Installments.Schema',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=15000;
IF @LateFeesLock<0 THROW 51310,N'Không lấy được khóa cập nhật phí trễ trả góp.',1;
IF OBJECT_ID(N'dbo.pos_installment_contracts',N'U') IS NULL OR OBJECT_ID(N'dbo.pos_installment_receipts',N'U') IS NULL
 THROW 51311,N'Cần chạy SQL trả góp 20261027 trước.',1;
IF COL_LENGTH(N'dbo.pos_installment_contracts',N'late_fee_per_day') IS NULL
 ALTER TABLE dbo.pos_installment_contracts ADD late_fee_per_day DECIMAL(18,0) NOT NULL CONSTRAINT DF_installment_daily_fee DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.pos_installment_contracts',N'late_fee_grace_days') IS NULL
 ALTER TABLE dbo.pos_installment_contracts ADD late_fee_grace_days INT NOT NULL CONSTRAINT DF_installment_grace DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'late_fee_amount') IS NULL
 ALTER TABLE dbo.pos_installment_receipts ADD late_fee_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_installment_receipt_fee DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'fee_policy_version') IS NULL
 ALTER TABLE dbo.pos_installment_receipts ADD fee_policy_version INT NOT NULL CONSTRAINT DF_installment_receipt_policy DEFAULT(0) WITH VALUES;
-- The base migration's sum constraint has an automatically generated name.
DECLARE @Constraint SYSNAME, @Drop NVARCHAR(MAX);
DECLARE OldSum CURSOR LOCAL FAST_FORWARD FOR
 SELECT name FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.pos_installment_receipts')
 AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(definition,N'[',N''),N']',N''),N'(',N''),N')',N''),N' ',N'')=N'amount=principal_amount+interest_amount';
OPEN OldSum; FETCH NEXT FROM OldSum INTO @Constraint;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Drop=N'ALTER TABLE dbo.pos_installment_receipts DROP CONSTRAINT '+QUOTENAME(@Constraint);
 EXEC(@Drop);
 FETCH NEXT FROM OldSum INTO @Constraint;
END;
CLOSE OldSum; DEALLOCATE OldSum;
IF OBJECT_ID(N'dbo.CK_installment_fee_policy',N'C') IS NULL
 EXEC(N'ALTER TABLE dbo.pos_installment_contracts WITH CHECK ADD CONSTRAINT CK_installment_fee_policy CHECK(late_fee_per_day BETWEEN 0 AND 1000000000 AND late_fee_grace_days BETWEEN 0 AND 365 AND (late_fee_per_day>0 OR late_fee_grace_days=0));');
IF OBJECT_ID(N'dbo.CK_installment_receipt_total',N'C') IS NULL
 EXEC(N'ALTER TABLE dbo.pos_installment_receipts WITH CHECK ADD CONSTRAINT CK_installment_receipt_total CHECK(late_fee_amount>=0 AND amount=principal_amount+interest_amount+late_fee_amount);');
IF OBJECT_ID(N'dbo.TR_InstallmentFeePolicy',N'TR') IS NOT NULL DROP TRIGGER dbo.TR_InstallmentFeePolicy;
EXEC(N'CREATE TRIGGER dbo.TR_InstallmentFeePolicy ON dbo.pos_installment_contracts AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.contract_id=i.contract_id
 WHERE i.late_fee_per_day<>d.late_fee_per_day OR i.late_fee_grace_days<>d.late_fee_grace_days)
 THROW 51312,N''Không thay đổi phí trễ của hồ sơ đã lập để giữ nguyên điều khoản và lịch sử.'',1;
END;');
IF OBJECT_ID(N'dbo.TR_InstallmentFeeClient',N'TR') IS NOT NULL DROP TRIGGER dbo.TR_InstallmentFeeClient;
EXEC(N'CREATE TRIGGER dbo.TR_InstallmentFeeClient ON dbo.pos_installment_receipts AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted r JOIN dbo.pos_installment_contracts c ON c.contract_id=r.contract_id
 WHERE (c.late_fee_per_day>0 AND r.fee_policy_version<>1) OR (c.late_fee_per_day=0 AND r.late_fee_amount<>0))
 THROW 51313,N''Cần bản phần mềm hỗ trợ phí trễ để thu hồ sơ này.'',1;
END;');
COMMIT TRANSACTION;
-- END INSTALLMENT SECTION: LateFees

-- BEGIN INSTALLMENT SECTION: SettlementPolicy
-- Settlement policy. Requires the Base and LateFees sections above.
-- 0 = interest through payment date (legacy); 1 = retain original scheduled total.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @SettlementPolicyLock INT;
EXEC @SettlementPolicyLock=sys.sp_getapplock @Resource=N'HoaTranPOS.Installments.Schema',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=15000;
IF @SettlementPolicyLock<0 THROW 51320,N'Không lấy được khóa cập nhật chính sách tất toán.',1;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'late_fee_amount') IS NULL
 THROW 51321,N'Cần chạy SQL trả góp và phí trễ trước.',1;
IF COL_LENGTH(N'dbo.pos_installment_contracts',N'settlement_policy') IS NULL
 ALTER TABLE dbo.pos_installment_contracts ADD settlement_policy INT NOT NULL CONSTRAINT DF_installment_settlement_policy DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.pos_installment_receipts',N'settlement_policy_version') IS NULL
 ALTER TABLE dbo.pos_installment_receipts ADD settlement_policy_version INT NOT NULL CONSTRAINT DF_installment_receipt_settlement_policy DEFAULT(0) WITH VALUES;
IF OBJECT_ID(N'dbo.CK_installment_settlement_policy',N'C') IS NULL
 EXEC(N'ALTER TABLE dbo.pos_installment_contracts WITH CHECK ADD CONSTRAINT CK_installment_settlement_policy CHECK(settlement_policy IN(0,1));');
IF OBJECT_ID(N'dbo.TR_InstallmentSettlementPolicy',N'TR') IS NOT NULL DROP TRIGGER dbo.TR_InstallmentSettlementPolicy;
EXEC(N'CREATE TRIGGER dbo.TR_InstallmentSettlementPolicy ON dbo.pos_installment_contracts AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.contract_id=i.contract_id WHERE i.settlement_policy<>d.settlement_policy)
 THROW 51322,N''Không thay đổi chính sách tất toán của hồ sơ đã lập.'',1;
END;');
IF OBJECT_ID(N'dbo.TR_InstallmentSettlementClient',N'TR') IS NOT NULL DROP TRIGGER dbo.TR_InstallmentSettlementClient;
EXEC(N'CREATE TRIGGER dbo.TR_InstallmentSettlementClient ON dbo.pos_installment_receipts AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted r JOIN dbo.pos_installment_contracts c ON c.contract_id=r.contract_id
 WHERE c.settlement_policy=1 AND r.settlement_policy_version<>1)
 THROW 51323,N''Cần cập nhật phần mềm để thu hồ sơ giữ tổng lãi theo lịch ban đầu.'',1;
END;');
COMMIT TRANSACTION;
-- END INSTALLMENT SECTION: SettlementPolicy

-- BEGIN INSTALLMENT SECTION: Menu
-- Optional installment-menu setting. Safe to apply repeatedly to existing shops.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @MenuLock INT;
EXEC @MenuLock = sys.sp_getapplock @Resource=N'HoaTranPOS.InstallmentMenu.Schema',
    @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=15000;
IF @MenuLock < 0 THROW 51330, N'Không lấy được khóa cập nhật cấu hình Trả góp.', 1;
IF OBJECT_ID(N'dbo.StoreInfo', N'U') IS NULL
    THROW 51331, N'Chưa có bảng thông tin cửa hàng để lưu cấu hình Trả góp.', 1;
IF COL_LENGTH(N'dbo.StoreInfo', N'show_installment_menu') IS NULL
    ALTER TABLE dbo.StoreInfo ADD show_installment_menu BIT NOT NULL
        CONSTRAINT DF_StoreInfo_show_installment_menu DEFAULT (0) WITH VALUES;
ELSE
BEGIN
    -- Change only the default for future rows; preserve every saved on/off choice.
    DECLARE @InstallmentMenuDefault SYSNAME, @InstallmentMenuDefaultDefinition NVARCHAR(MAX);
    SELECT @InstallmentMenuDefault = d.name, @InstallmentMenuDefaultDefinition = d.definition
    FROM sys.default_constraints d
    JOIN sys.columns c ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
    WHERE d.parent_object_id = OBJECT_ID(N'dbo.StoreInfo') AND c.name = N'show_installment_menu';
    IF @InstallmentMenuDefault IS NULL OR REPLACE(REPLACE(REPLACE(@InstallmentMenuDefaultDefinition,N'(',N''),N')',N''),N' ',N'') <> N'0'
    BEGIN
        IF @InstallmentMenuDefault IS NOT NULL
        BEGIN
            DECLARE @InstallmentMenuDropSql NVARCHAR(400) = N'ALTER TABLE dbo.StoreInfo DROP CONSTRAINT ' + QUOTENAME(@InstallmentMenuDefault);
            EXEC sys.sp_executesql @InstallmentMenuDropSql;
        END;
        ALTER TABLE dbo.StoreInfo ADD CONSTRAINT DF_StoreInfo_show_installment_menu DEFAULT (0) FOR show_installment_menu;
    END;
END;
COMMIT;
-- END INSTALLMENT SECTION: Menu

