/*
    HoaTran POS - Optional cashier shift management / Z-Report K80
    Safe and idempotent. The application runs the equivalent migration itself;
    this file is retained for deployment review and manual recovery only.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.StoreInfo', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.StoreInfo', N'enable_shift_management') IS NULL
BEGIN
    ALTER TABLE dbo.StoreInfo ADD enable_shift_management BIT NOT NULL
        CONSTRAINT DF_StoreInfo_enable_shift_management DEFAULT (0) WITH VALUES;
END;

IF OBJECT_ID(N'dbo.work_shifts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.work_shifts
    (
        shift_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_work_shifts PRIMARY KEY,
        shift_code NVARCHAR(50) NOT NULL,
        cashier_id INT NOT NULL,
        cashier_name NVARCHAR(100) NULL,
        opened_at DATETIME NOT NULL CONSTRAINT DF_work_shifts_opened_at DEFAULT(GETDATE()),
        closed_at DATETIME NULL,
        initial_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_initial_cash DEFAULT(0),
        cash_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_sales DEFAULT(0),
        bank_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_bank_sales DEFAULT(0),
        wallet_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_wallet_sales DEFAULT(0),
        cash_debt_collected DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_debt DEFAULT(0),
        cash_expenses DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_expenses DEFAULT(0),
        expected_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_expected_cash DEFAULT(0),
        actual_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_actual_cash DEFAULT(0),
        difference_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_difference DEFAULT(0),
        order_count INT NOT NULL CONSTRAINT DF_work_shifts_order_count DEFAULT(0),
        status NVARCHAR(20) NOT NULL CONSTRAINT DF_work_shifts_status DEFAULT(N'OPEN'),
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_work_shifts_created_at DEFAULT(GETDATE())
    );
END;

IF COL_LENGTH(N'dbo.work_shifts', N'shift_code') IS NULL
    ALTER TABLE dbo.work_shifts ADD shift_code NVARCHAR(50) NOT NULL CONSTRAINT DF_work_shifts_shift_code_upgrade DEFAULT(N'') WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'cashier_id') IS NULL
    ALTER TABLE dbo.work_shifts ADD cashier_id INT NOT NULL CONSTRAINT DF_work_shifts_cashier_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'cashier_name') IS NULL
    ALTER TABLE dbo.work_shifts ADD cashier_name NVARCHAR(100) NULL;
IF COL_LENGTH(N'dbo.work_shifts', N'opened_at') IS NULL
    ALTER TABLE dbo.work_shifts ADD opened_at DATETIME NOT NULL CONSTRAINT DF_work_shifts_opened_upgrade DEFAULT(GETDATE()) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'closed_at') IS NULL
    ALTER TABLE dbo.work_shifts ADD closed_at DATETIME NULL;
IF COL_LENGTH(N'dbo.work_shifts', N'initial_cash') IS NULL
    ALTER TABLE dbo.work_shifts ADD initial_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_initial_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'cash_sales') IS NULL
    ALTER TABLE dbo.work_shifts ADD cash_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_sales_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'bank_sales') IS NULL
    ALTER TABLE dbo.work_shifts ADD bank_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_bank_sales_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'wallet_sales') IS NULL
    ALTER TABLE dbo.work_shifts ADD wallet_sales DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_wallet_sales_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'cash_debt_collected') IS NULL
    ALTER TABLE dbo.work_shifts ADD cash_debt_collected DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_debt_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'cash_expenses') IS NULL
    ALTER TABLE dbo.work_shifts ADD cash_expenses DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_cash_expenses_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'expected_cash') IS NULL
    ALTER TABLE dbo.work_shifts ADD expected_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_expected_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'actual_cash') IS NULL
    ALTER TABLE dbo.work_shifts ADD actual_cash DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_actual_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'difference_amount') IS NULL
    ALTER TABLE dbo.work_shifts ADD difference_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_work_shifts_difference_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'order_count') IS NULL
    ALTER TABLE dbo.work_shifts ADD order_count INT NOT NULL CONSTRAINT DF_work_shifts_count_upgrade DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'status') IS NULL
    ALTER TABLE dbo.work_shifts ADD status NVARCHAR(20) NOT NULL CONSTRAINT DF_work_shifts_status_upgrade DEFAULT(N'OPEN') WITH VALUES;
IF COL_LENGTH(N'dbo.work_shifts', N'note') IS NULL
    ALTER TABLE dbo.work_shifts ADD note NVARCHAR(500) NULL;
IF COL_LENGTH(N'dbo.work_shifts', N'created_at') IS NULL
    ALTER TABLE dbo.work_shifts ADD created_at DATETIME NOT NULL CONSTRAINT DF_work_shifts_created_upgrade DEFAULT(GETDATE()) WITH VALUES;

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.work_shifts')
      AND name = N'UX_work_shifts_cashier_open'
)
AND NOT EXISTS
(
    SELECT cashier_id
    FROM dbo.work_shifts
    WHERE status = N'OPEN'
    GROUP BY cashier_id
    HAVING COUNT(*) > 1
)
    CREATE UNIQUE INDEX UX_work_shifts_cashier_open
        ON dbo.work_shifts(cashier_id) WHERE status = N'OPEN';

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.work_shifts')
      AND name = N'UX_work_shifts_shift_code'
)
AND NOT EXISTS
(
    SELECT shift_code FROM dbo.work_shifts
    GROUP BY shift_code HAVING COUNT(*) > 1
)
    CREATE UNIQUE INDEX UX_work_shifts_shift_code ON dbo.work_shifts(shift_code);

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.work_shifts')
      AND name = N'IX_work_shifts_cashier_opened_at'
)
    CREATE INDEX IX_work_shifts_cashier_opened_at
        ON dbo.work_shifts(cashier_id, opened_at DESC);

COMMIT TRANSACTION;
