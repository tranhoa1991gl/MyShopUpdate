SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.repair_orders', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.repair_orders
        (
            repair_order_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_orders PRIMARY KEY,
            repair_code NVARCHAR(30) NOT NULL,
            received_at DATETIME NOT NULL CONSTRAINT DF_repair_orders_received_at DEFAULT (GETDATE()),
            customer_id INT NULL,
            customer_name NVARCHAR(150) NOT NULL,
            customer_phone NVARCHAR(30) NULL,
            customer_address NVARCHAR(500) NULL,
            device_type NVARCHAR(100) NOT NULL,
            brand NVARCHAR(100) NULL,
            model NVARCHAR(150) NULL,
            imei NVARCHAR(100) NULL,
            serial_number NVARCHAR(100) NULL,
            color NVARCHAR(80) NULL,
            device_access_note NVARCHAR(500) NULL,
            appearance_condition NVARCHAR(MAX) NULL,
            device_condition NVARCHAR(MAX) NULL,
            customer_issue NVARCHAR(MAX) NOT NULL,
            accessories NVARCHAR(1000) NULL,
            note NVARCHAR(MAX) NULL,
            receiver_employee_id INT NULL,
            primary_technician_id INT NULL,
            promised_at DATETIME NULL,
            estimated_completion_at DATETIME NULL,
            status NVARCHAR(30) NOT NULL CONSTRAINT DF_repair_orders_status DEFAULT (N'RECEIVED'),
            quote_status NVARCHAR(20) NOT NULL CONSTRAINT DF_repair_orders_quote_status DEFAULT (N'DRAFT'),
            parts_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_parts_amount DEFAULT (0),
            labor_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_labor_amount DEFAULT (0),
            service_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_service_amount DEFAULT (0),
            other_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_other_amount DEFAULT (0),
            discount_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_discount_amount DEFAULT (0),
            final_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_final_amount DEFAULT (0),
            paid_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_orders_paid_amount DEFAULT (0),
            payment_status NVARCHAR(20) NOT NULL CONSTRAINT DF_repair_orders_payment_status DEFAULT (N'UNPAID'),
            quote_sent_at DATETIME NULL,
            quote_approved_at DATETIME NULL,
            completed_at DATETIME NULL,
            delivered_at DATETIME NULL,
            warranty_start_date DATE NULL,
            warranty_months INT NOT NULL CONSTRAINT DF_repair_orders_warranty_months DEFAULT (0),
            warranty_end_date DATE NULL,
            warranty_content NVARCHAR(1000) NULL,
            warranty_source_repair_id INT NULL,
            close_reason NVARCHAR(500) NULL,
            created_at DATETIME NOT NULL CONSTRAINT DF_repair_orders_created_at DEFAULT (GETDATE()),
            created_by NVARCHAR(100) NULL,
            updated_at DATETIME NOT NULL CONSTRAINT DF_repair_orders_updated_at DEFAULT (GETDATE()),
            updated_by NVARCHAR(100) NULL,
            row_version ROWVERSION NOT NULL
        );
    END;

    IF OBJECT_ID(N'dbo.repair_order_items', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.repair_order_items
        (
            repair_item_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_order_items PRIMARY KEY,
            repair_order_id INT NOT NULL,
            line_type NVARCHAR(20) NOT NULL,
            product_id INT NULL,
            product_variant_id INT NULL,
            unit_id INT NULL,
            description NVARCHAR(500) NOT NULL,
            input_quantity DECIMAL(18,3) NOT NULL CONSTRAINT DF_repair_order_items_input_quantity DEFAULT (1),
            base_quantity DECIMAL(18,3) NOT NULL CONSTRAINT DF_repair_order_items_base_quantity DEFAULT (1),
            unit_conversion_to_base DECIMAL(18,6) NOT NULL CONSTRAINT DF_repair_order_items_conversion DEFAULT (1),
            unit_name_snapshot NVARCHAR(50) NULL,
            variant_name_snapshot NVARCHAR(250) NULL,
            unit_price DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_order_items_unit_price DEFAULT (0),
            cost_price DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_order_items_cost_price DEFAULT (0),
            customer_labor_charge DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_order_items_customer_labor_charge DEFAULT (0),
            technician_id INT NULL,
            commission_type NVARCHAR(20) NULL,
            commission_value DECIMAL(18,4) NOT NULL CONSTRAINT DF_repair_order_items_commission_value DEFAULT (0),
            technician_commission_amount DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_order_items_commission_amount DEFAULT (0),
            item_status NVARCHAR(20) NOT NULL CONSTRAINT DF_repair_order_items_status DEFAULT (N'PLANNED'),
            serial_number NVARCHAR(100) NULL,
            warranty_months INT NOT NULL CONSTRAINT DF_repair_order_items_warranty_months DEFAULT (0),
            note NVARCHAR(500) NULL,
            sort_order INT NOT NULL CONSTRAINT DF_repair_order_items_sort DEFAULT (0),
            created_at DATETIME NOT NULL CONSTRAINT DF_repair_order_items_created_at DEFAULT (GETDATE()),
            updated_at DATETIME NOT NULL CONSTRAINT DF_repair_order_items_updated_at DEFAULT (GETDATE())
        );
    END;

    IF OBJECT_ID(N'dbo.repair_order_events', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.repair_order_events
        (
            repair_event_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_order_events PRIMARY KEY,
            repair_order_id INT NOT NULL,
            event_type NVARCHAR(30) NOT NULL,
            old_status NVARCHAR(30) NULL,
            new_status NVARCHAR(30) NULL,
            content NVARCHAR(MAX) NULL,
            employee_id INT NULL,
            created_at DATETIME NOT NULL CONSTRAINT DF_repair_order_events_created_at DEFAULT (GETDATE()),
            created_by NVARCHAR(100) NULL
        );
    END;

    IF OBJECT_ID(N'dbo.repair_part_movements', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.repair_part_movements
        (
            repair_movement_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_part_movements PRIMARY KEY,
            repair_order_id INT NOT NULL,
            repair_item_id INT NOT NULL,
            movement_type NVARCHAR(10) NOT NULL,
            base_quantity DECIMAL(18,3) NOT NULL,
            cost_price DECIMAL(18,2) NOT NULL CONSTRAINT DF_repair_part_movements_cost DEFAULT (0),
            stock_before DECIMAL(18,3) NULL,
            stock_after DECIMAL(18,3) NULL,
            serial_number NVARCHAR(100) NULL,
            operation_key NVARCHAR(100) NOT NULL,
            reason NVARCHAR(500) NULL,
            created_at DATETIME NOT NULL CONSTRAINT DF_repair_part_movements_created_at DEFAULT (GETDATE()),
            created_by NVARCHAR(100) NULL
        );
    END;

    IF OBJECT_ID(N'dbo.repair_payments', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.repair_payments
        (
            repair_payment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_payments PRIMARY KEY,
            repair_order_id INT NOT NULL,
            payment_date DATETIME NOT NULL CONSTRAINT DF_repair_payments_date DEFAULT (GETDATE()),
            amount DECIMAL(18,2) NOT NULL,
            payment_method NVARCHAR(50) NOT NULL,
            note NVARCHAR(500) NULL,
            reference_code NVARCHAR(100) NULL,
            is_void BIT NOT NULL CONSTRAINT DF_repair_payments_void DEFAULT (0),
            voided_at DATETIME NULL,
            voided_by NVARCHAR(100) NULL,
            void_reason NVARCHAR(500) NULL,
            created_at DATETIME NOT NULL CONSTRAINT DF_repair_payments_created_at DEFAULT (GETDATE()),
            created_by NVARCHAR(100) NULL
        );
    END;

    IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'repair_order_id') IS NULL
        ALTER TABLE dbo.customer_wallet_transactions ADD repair_order_id INT NULL;

    IF COL_LENGTH(N'dbo.product_serials', N'repair_order_item_id') IS NULL
        ALTER TABLE dbo.product_serials ADD repair_order_item_id INT NULL;

    IF COL_LENGTH(N'dbo.repair_order_items', N'customer_labor_charge') IS NULL
        ALTER TABLE dbo.repair_order_items ADD customer_labor_charge DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_repair_order_items_customer_labor_charge DEFAULT (0);

    IF COL_LENGTH(N'dbo.employee_payrolls', N'repair_commission_amount') IS NULL
        ALTER TABLE dbo.employee_payrolls ADD repair_commission_amount DECIMAL(18,0) NOT NULL
            CONSTRAINT DF_employee_payrolls_repair_commission DEFAULT (0);

    IF COL_LENGTH(N'dbo.Users', N'CanViewRepairs') IS NULL
        ALTER TABLE dbo.Users ADD CanViewRepairs BIT NOT NULL CONSTRAINT DF_Users_CanViewRepairs DEFAULT (0);
    IF COL_LENGTH(N'dbo.Users', N'CanEditRepairs') IS NULL
        ALTER TABLE dbo.Users ADD CanEditRepairs BIT NOT NULL CONSTRAINT DF_Users_CanEditRepairs DEFAULT (0);
    IF COL_LENGTH(N'dbo.Users', N'CanUseRepairParts') IS NULL
        ALTER TABLE dbo.Users ADD CanUseRepairParts BIT NOT NULL CONSTRAINT DF_Users_CanUseRepairParts DEFAULT (0);
    IF COL_LENGTH(N'dbo.Users', N'CanCollectRepairPayment') IS NULL
        ALTER TABLE dbo.Users ADD CanCollectRepairPayment BIT NOT NULL CONSTRAINT DF_Users_CanCollectRepairPayment DEFAULT (0);
    IF COL_LENGTH(N'dbo.Users', N'CanCancelRepairs') IS NULL
        ALTER TABLE dbo.Users ADD CanCancelRepairs BIT NOT NULL CONSTRAINT DF_Users_CanCancelRepairs DEFAULT (0);

    EXEC sys.sp_executesql N'
        UPDATE dbo.Users
        SET CanViewRepairs = 1,
            CanEditRepairs = 1,
            CanUseRepairParts = 1,
            CanCollectRepairPayment = 1,
            CanCancelRepairs = 1
        WHERE RoleId = 1 OR LOWER(ISNULL(Username, N'''') ) = N''admin'';';

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_orders') AND name = N'UX_repair_orders_code')
        CREATE UNIQUE INDEX UX_repair_orders_code ON dbo.repair_orders(repair_code);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_orders') AND name = N'IX_repair_orders_received_status')
        CREATE INDEX IX_repair_orders_received_status ON dbo.repair_orders(received_at DESC, status);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_orders') AND name = N'IX_repair_orders_customer')
        CREATE INDEX IX_repair_orders_customer ON dbo.repair_orders(customer_id, customer_phone);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_orders') AND name = N'IX_repair_orders_device_lookup')
        CREATE INDEX IX_repair_orders_device_lookup ON dbo.repair_orders(imei, serial_number);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_order_items') AND name = N'IX_repair_order_items_order')
        CREATE INDEX IX_repair_order_items_order ON dbo.repair_order_items(repair_order_id, sort_order);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_order_events') AND name = N'IX_repair_order_events_order')
        CREATE INDEX IX_repair_order_events_order ON dbo.repair_order_events(repair_order_id, created_at DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_part_movements') AND name = N'UX_repair_part_movements_operation')
        CREATE UNIQUE INDEX UX_repair_part_movements_operation ON dbo.repair_part_movements(operation_key);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.repair_payments') AND name = N'IX_repair_payments_order')
        CREATE INDEX IX_repair_payments_order ON dbo.repair_payments(repair_order_id, payment_date);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_orders_customer')
        ALTER TABLE dbo.repair_orders ADD CONSTRAINT FK_repair_orders_customer FOREIGN KEY(customer_id) REFERENCES dbo.customers(customer_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_orders_receiver')
        ALTER TABLE dbo.repair_orders ADD CONSTRAINT FK_repair_orders_receiver FOREIGN KEY(receiver_employee_id) REFERENCES dbo.employees(employee_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_orders_technician')
        ALTER TABLE dbo.repair_orders ADD CONSTRAINT FK_repair_orders_technician FOREIGN KEY(primary_technician_id) REFERENCES dbo.employees(employee_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_orders_warranty_source')
        ALTER TABLE dbo.repair_orders ADD CONSTRAINT FK_repair_orders_warranty_source FOREIGN KEY(warranty_source_repair_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_items_order')
        ALTER TABLE dbo.repair_order_items ADD CONSTRAINT FK_repair_items_order FOREIGN KEY(repair_order_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_items_product')
        ALTER TABLE dbo.repair_order_items ADD CONSTRAINT FK_repair_items_product FOREIGN KEY(product_id) REFERENCES dbo.products(product_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_items_variant')
        ALTER TABLE dbo.repair_order_items ADD CONSTRAINT FK_repair_items_variant FOREIGN KEY(product_variant_id) REFERENCES dbo.product_variants(variant_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_items_unit')
        ALTER TABLE dbo.repair_order_items ADD CONSTRAINT FK_repair_items_unit FOREIGN KEY(unit_id) REFERENCES dbo.Units(unit_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_items_technician')
        ALTER TABLE dbo.repair_order_items ADD CONSTRAINT FK_repair_items_technician FOREIGN KEY(technician_id) REFERENCES dbo.employees(employee_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_events_order')
        ALTER TABLE dbo.repair_order_events ADD CONSTRAINT FK_repair_events_order FOREIGN KEY(repair_order_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_movements_order')
        ALTER TABLE dbo.repair_part_movements ADD CONSTRAINT FK_repair_movements_order FOREIGN KEY(repair_order_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_movements_item')
        ALTER TABLE dbo.repair_part_movements ADD CONSTRAINT FK_repair_movements_item FOREIGN KEY(repair_item_id) REFERENCES dbo.repair_order_items(repair_item_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_repair_payments_order')
        ALTER TABLE dbo.repair_payments ADD CONSTRAINT FK_repair_payments_order FOREIGN KEY(repair_order_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_wallet_transactions_repair')
        ALTER TABLE dbo.customer_wallet_transactions ADD CONSTRAINT FK_wallet_transactions_repair FOREIGN KEY(repair_order_id) REFERENCES dbo.repair_orders(repair_order_id);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_product_serials_repair_item')
        ALTER TABLE dbo.product_serials ADD CONSTRAINT FK_product_serials_repair_item FOREIGN KEY(repair_order_item_id) REFERENCES dbo.repair_order_items(repair_item_id);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
