SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.supplier_debt_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.supplier_debt_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_supplier_debt_adjustments PRIMARY KEY,
        supplier_id INT NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_supplier_debt_adjustments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        adjustment_type NVARCHAR(30) NOT NULL CONSTRAINT DF_supplier_debt_adjustments_type DEFAULT(N'DISCOUNT'),
        employee_id INT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_supplier_debt_adjustments_created DEFAULT(GETDATE()),
        CONSTRAINT CK_supplier_debt_adjustments_amount CHECK(amount > 0),
        CONSTRAINT FK_supplier_debt_adjustments_suppliers FOREIGN KEY(supplier_id) REFERENCES dbo.suppliers(supplier_id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.supplier_debt_adjustments') AND name=N'IX_supplier_debt_adjustments_supplier_date')
    CREATE INDEX IX_supplier_debt_adjustments_supplier_date ON dbo.supplier_debt_adjustments(supplier_id,adjustment_date,adjustment_id);

IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_supplier_debt_adjustments_employees')
    ALTER TABLE dbo.supplier_debt_adjustments WITH CHECK
    ADD CONSTRAINT FK_supplier_debt_adjustments_employees FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);

IF OBJECT_ID(N'dbo.supplier_debt_discount_allocations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.supplier_debt_discount_allocations
    (
        allocation_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_supplier_debt_discount_allocations PRIMARY KEY,
        adjustment_id INT NOT NULL,
        import_id INT NOT NULL,
        amount DECIMAL(18,0) NOT NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_supplier_debt_discount_allocations_created DEFAULT(GETDATE()),
        CONSTRAINT CK_supplier_debt_discount_allocations_amount CHECK(amount > 0),
        CONSTRAINT UQ_supplier_debt_discount_allocations_adjustment_import UNIQUE(adjustment_id,import_id),
        CONSTRAINT FK_supplier_debt_discount_allocations_adjustment FOREIGN KEY(adjustment_id) REFERENCES dbo.supplier_debt_adjustments(adjustment_id) ON DELETE CASCADE,
        CONSTRAINT FK_supplier_debt_discount_allocations_import FOREIGN KEY(import_id) REFERENCES dbo.imports(import_id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.supplier_debt_discount_allocations') AND name=N'IX_supplier_debt_discount_allocations_import')
    CREATE INDEX IX_supplier_debt_discount_allocations_import ON dbo.supplier_debt_discount_allocations(import_id,adjustment_id);

COMMIT TRANSACTION;
