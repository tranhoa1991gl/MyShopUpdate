SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.customer_debt_discount_allocations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customer_debt_discount_allocations
    (
        allocation_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_customer_debt_discount_allocations PRIMARY KEY,
        adjustment_id INT NOT NULL,
        order_id INT NOT NULL,
        amount DECIMAL(18,0) NOT NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_customer_debt_discount_allocations_created DEFAULT (GETDATE()),
        CONSTRAINT CK_customer_debt_discount_allocations_amount CHECK (amount > 0),
        CONSTRAINT UQ_customer_debt_discount_allocations_adjustment_order UNIQUE (adjustment_id, order_id)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_customer_debt_discount_allocations_amount'
      AND parent_object_id = OBJECT_ID(N'dbo.customer_debt_discount_allocations')
)
    ALTER TABLE dbo.customer_debt_discount_allocations WITH CHECK
    ADD CONSTRAINT CK_customer_debt_discount_allocations_amount CHECK (amount > 0);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.customer_debt_discount_allocations')
      AND name = N'UQ_customer_debt_discount_allocations_adjustment_order'
)
    ALTER TABLE dbo.customer_debt_discount_allocations
    ADD CONSTRAINT UQ_customer_debt_discount_allocations_adjustment_order UNIQUE (adjustment_id, order_id);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_customer_debt_discount_allocations_adjustment'
)
    ALTER TABLE dbo.customer_debt_discount_allocations WITH CHECK
    ADD CONSTRAINT FK_customer_debt_discount_allocations_adjustment
    FOREIGN KEY(adjustment_id) REFERENCES dbo.customer_debt_adjustments(adjustment_id)
    ON DELETE CASCADE;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_customer_debt_discount_allocations_order'
)
    ALTER TABLE dbo.customer_debt_discount_allocations WITH CHECK
    ADD CONSTRAINT FK_customer_debt_discount_allocations_order
    FOREIGN KEY(order_id) REFERENCES dbo.orders(order_id);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.customer_debt_discount_allocations')
      AND name = N'IX_customer_debt_discount_allocations_order'
)
    CREATE INDEX IX_customer_debt_discount_allocations_order
    ON dbo.customer_debt_discount_allocations(order_id, adjustment_id);
GO

IF OBJECT_ID(N'dbo.TR_customer_debt_discount_allocations_validate', N'TR') IS NULL
    EXEC(N'CREATE TRIGGER dbo.TR_customer_debt_discount_allocations_validate ON dbo.customer_debt_discount_allocations AFTER INSERT, UPDATE AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER TRIGGER dbo.TR_customer_debt_discount_allocations_validate
ON dbo.customer_debt_discount_allocations
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.customer_debt_adjustments a ON a.adjustment_id = i.adjustment_id
        INNER JOIN dbo.orders o ON o.order_id = i.order_id
        WHERE a.customer_id <> o.customer_id
    )
    BEGIN
        RAISERROR(N'Hóa đơn phân bổ không thuộc khách hàng của phiếu chiết khấu.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM
        (
            SELECT a.adjustment_id, a.amount AS AdjustmentAmount, SUM(ISNULL(da.amount, 0)) AS AllocatedAmount
            FROM dbo.customer_debt_adjustments a
            INNER JOIN (SELECT DISTINCT adjustment_id FROM inserted) x ON x.adjustment_id = a.adjustment_id
            LEFT JOIN dbo.customer_debt_discount_allocations da ON da.adjustment_id = a.adjustment_id
            GROUP BY a.adjustment_id, a.amount
        ) q
        WHERE q.AllocatedAmount > q.AdjustmentAmount
    )
    BEGIN
        RAISERROR(N'Tổng chiết khấu phân bổ vượt quá giá trị phiếu chiết khấu.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

