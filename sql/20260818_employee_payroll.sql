SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Bảng lương cố định theo tháng.
   Doanh thu/hoa hồng được snapshot khi tạo bảng lương; phụ cấp, thưởng, trừ, ứng và thanh toán
   được lưu thành từng phát sinh để không mất lịch sử khi điều chỉnh hoặc hủy.
*/

IF OBJECT_ID(N'dbo.employee_payroll_settings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_settings
    (
        employee_id INT NOT NULL CONSTRAINT PK_employee_payroll_settings PRIMARY KEY,
        base_salary DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payroll_settings_base DEFAULT(0),
        commission_rate DECIMAL(9,4) NOT NULL CONSTRAINT DF_employee_payroll_settings_rate DEFAULT(0),
        updated_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_settings_updated DEFAULT(GETDATE()),
        updated_by NVARCHAR(100) NULL
    );
END;

IF OBJECT_ID(N'dbo.employee_payrolls', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payrolls
    (
        payroll_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payrolls PRIMARY KEY,
        payroll_month DATE NOT NULL,
        employee_id INT NOT NULL,
        employee_name NVARCHAR(200) NOT NULL,
        role_name NVARCHAR(100) NULL,
        base_salary DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_base DEFAULT(0),
        revenue_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_revenue DEFAULT(0),
        commission_rate DECIMAL(9,4) NOT NULL CONSTRAINT DF_employee_payrolls_rate DEFAULT(0),
        commission_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_commission DEFAULT(0),
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payrolls_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        updated_at DATETIME NOT NULL CONSTRAINT DF_employee_payrolls_updated DEFAULT(GETDATE()),
        updated_by NVARCHAR(100) NULL,
        CONSTRAINT UQ_employee_payrolls_month_employee UNIQUE(payroll_month, employee_id)
    );
END;

IF OBJECT_ID(N'dbo.employee_payroll_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payroll_adjustments PRIMARY KEY,
        payroll_id INT NOT NULL,
        adjustment_type NVARCHAR(20) NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_employee_payroll_adjustments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_adjustments_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        is_void BIT NOT NULL CONSTRAINT DF_employee_payroll_adjustments_void DEFAULT(0),
        voided_at DATETIME NULL,
        voided_by NVARCHAR(100) NULL,
        CONSTRAINT CK_employee_payroll_adjustments_type CHECK(adjustment_type IN (N'ALLOWANCE', N'BONUS', N'DEDUCTION')),
        CONSTRAINT CK_employee_payroll_adjustments_amount CHECK(amount > 0)
    );
END;

IF OBJECT_ID(N'dbo.employee_payroll_payments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_payments
    (
        payment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payroll_payments PRIMARY KEY,
        payroll_id INT NOT NULL,
        payment_type NVARCHAR(20) NOT NULL,
        payment_date DATETIME NOT NULL CONSTRAINT DF_employee_payroll_payments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        payment_method NVARCHAR(50) NULL,
        note NVARCHAR(500) NULL,
        reference_code NVARCHAR(100) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_payments_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        is_void BIT NOT NULL CONSTRAINT DF_employee_payroll_payments_void DEFAULT(0),
        voided_at DATETIME NULL,
        voided_by NVARCHAR(100) NULL,
        CONSTRAINT CK_employee_payroll_payments_type CHECK(payment_type IN (N'ADVANCE', N'SETTLEMENT')),
        CONSTRAINT CK_employee_payroll_payments_amount CHECK(amount > 0)
    );
END;

IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_employee_payroll_settings_employee')
    ALTER TABLE dbo.employee_payroll_settings WITH CHECK
    ADD CONSTRAINT FK_employee_payroll_settings_employee FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);

IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_employee_payrolls_employee')
    ALTER TABLE dbo.employee_payrolls WITH CHECK
    ADD CONSTRAINT FK_employee_payrolls_employee FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_employee_payroll_adjustments_payroll')
    ALTER TABLE dbo.employee_payroll_adjustments WITH CHECK
    ADD CONSTRAINT FK_employee_payroll_adjustments_payroll FOREIGN KEY(payroll_id) REFERENCES dbo.employee_payrolls(payroll_id);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_employee_payroll_payments_payroll')
    ALTER TABLE dbo.employee_payroll_payments WITH CHECK
    ADD CONSTRAINT FK_employee_payroll_payments_payroll FOREIGN KEY(payroll_id) REFERENCES dbo.employee_payrolls(payroll_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.employee_payrolls') AND name = N'IX_employee_payrolls_month_employee')
    CREATE INDEX IX_employee_payrolls_month_employee ON dbo.employee_payrolls(payroll_month, employee_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.employee_payroll_adjustments') AND name = N'IX_employee_payroll_adjustments_payroll')
    CREATE INDEX IX_employee_payroll_adjustments_payroll ON dbo.employee_payroll_adjustments(payroll_id, is_void, adjustment_date);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.employee_payroll_payments') AND name = N'IX_employee_payroll_payments_payroll')
    CREATE INDEX IX_employee_payroll_payments_payroll ON dbo.employee_payroll_payments(payroll_id, is_void, payment_date);

COMMIT TRANSACTION;
