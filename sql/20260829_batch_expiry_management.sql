/*
    Quản lý lô / hạn sử dụng - MyShop
    - Idempotent: có thể chạy lại an toàn.
    - Không sinh lô giả cho dữ liệu tồn cũ.
    - Tồn tổng vẫn nằm ở products/product_variants; product_batches là sổ chi tiết.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.products', N'has_batch_expiry') IS NULL
BEGIN
    ALTER TABLE dbo.products
    ADD has_batch_expiry BIT NOT NULL
        CONSTRAINT DF_products_has_batch_expiry DEFAULT (0) WITH VALUES;
END;

IF OBJECT_ID(N'dbo.product_batches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_batches
    (
        batch_id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_batches PRIMARY KEY,
        product_id            INT NOT NULL,
        variant_id            INT NULL,
        import_detail_id      INT NOT NULL,
        supplier_id           INT NULL,
        batch_code            NVARCHAR(100) NOT NULL,
        manufacture_date      DATE NULL,
        expiry_date           DATE NULL,
        received_date         DATETIME NOT NULL CONSTRAINT DF_product_batches_received_date DEFAULT (GETDATE()),
        quantity_imported     DECIMAL(18,3) NOT NULL,
        quantity_remaining    DECIMAL(18,3) NOT NULL,
        cost_price            DECIMAL(18,2) NOT NULL,
        is_posted             BIT NOT NULL CONSTRAINT DF_product_batches_is_posted DEFAULT (1),
        is_cancelled          BIT NOT NULL CONSTRAINT DF_product_batches_is_cancelled DEFAULT (0),
        created_at            DATETIME NOT NULL CONSTRAINT DF_product_batches_created_at DEFAULT (GETDATE()),
        updated_at            DATETIME NOT NULL CONSTRAINT DF_product_batches_updated_at DEFAULT (GETDATE()),
        CONSTRAINT FK_product_batches_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_product_batches_variant FOREIGN KEY (variant_id) REFERENCES dbo.product_variants(variant_id),
        CONSTRAINT FK_product_batches_import_detail FOREIGN KEY (import_detail_id) REFERENCES dbo.import_details(import_detail_id),
        CONSTRAINT CK_product_batches_imported CHECK (quantity_imported > 0),
        CONSTRAINT CK_product_batches_remaining CHECK (quantity_remaining >= 0 AND quantity_remaining <= quantity_imported),
        CONSTRAINT CK_product_batches_dates CHECK (manufacture_date IS NULL OR expiry_date IS NULL OR manufacture_date <= expiry_date)
    );
END;

IF COL_LENGTH(N'dbo.product_batches', N'is_posted') IS NULL
    ALTER TABLE dbo.product_batches ADD is_posted BIT NOT NULL CONSTRAINT DF_product_batches_is_posted DEFAULT (1) WITH VALUES;
IF COL_LENGTH(N'dbo.product_batches', N'is_cancelled') IS NULL
    ALTER TABLE dbo.product_batches ADD is_cancelled BIT NOT NULL CONSTRAINT DF_product_batches_is_cancelled DEFAULT (0) WITH VALUES;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_product_batches_product')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT FK_product_batches_product FOREIGN KEY(product_id) REFERENCES dbo.products(product_id);
IF OBJECT_ID(N'dbo.product_variants',N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_product_batches_variant')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT FK_product_batches_variant FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_product_batches_import_detail')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT FK_product_batches_import_detail FOREIGN KEY(import_detail_id) REFERENCES dbo.import_details(import_detail_id);
IF OBJECT_ID(N'dbo.suppliers',N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_product_batches_supplier')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT FK_product_batches_supplier FOREIGN KEY(supplier_id) REFERENCES dbo.suppliers(supplier_id);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_product_batches_imported')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT CK_product_batches_imported CHECK(quantity_imported>0);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_product_batches_remaining')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT CK_product_batches_remaining CHECK(quantity_remaining>=0 AND quantity_remaining<=quantity_imported);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_product_batches_dates')
    ALTER TABLE dbo.product_batches WITH CHECK ADD CONSTRAINT CK_product_batches_dates CHECK(manufacture_date IS NULL OR expiry_date IS NULL OR manufacture_date<=expiry_date);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.product_batches') AND name = N'UX_product_batches_import_detail_code')
    CREATE UNIQUE INDEX UX_product_batches_import_detail_code
        ON dbo.product_batches(import_detail_id, batch_code);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.product_batches') AND name = N'IX_product_batches_fefo')
    CREATE INDEX IX_product_batches_fefo
        ON dbo.product_batches(product_id, variant_id, expiry_date, received_date, batch_id)
        INCLUDE(batch_code, quantity_remaining, cost_price, import_detail_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.product_batches') AND name = N'IX_product_batches_expiry')
    CREATE INDEX IX_product_batches_expiry
        ON dbo.product_batches(expiry_date, quantity_remaining)
        INCLUDE(product_id, variant_id, batch_code);

IF OBJECT_ID(N'dbo.order_item_batches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.order_item_batches
    (
        allocation_id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_order_item_batches PRIMARY KEY,
        order_item_id        INT NOT NULL,
        batch_id             INT NOT NULL,
        movement_type        NVARCHAR(30) NOT NULL,
        quantity_base        DECIMAL(18,3) NOT NULL,
        unit_cost            DECIMAL(18,2) NOT NULL,
        source_allocation_id INT NULL,
        created_at           DATETIME NOT NULL CONSTRAINT DF_order_item_batches_created_at DEFAULT (GETDATE()),
        CONSTRAINT FK_order_item_batches_item FOREIGN KEY (order_item_id) REFERENCES dbo.order_items(order_item_id),
        CONSTRAINT FK_order_item_batches_batch FOREIGN KEY (batch_id) REFERENCES dbo.product_batches(batch_id),
        CONSTRAINT FK_order_item_batches_source FOREIGN KEY (source_allocation_id) REFERENCES dbo.order_item_batches(allocation_id),
        CONSTRAINT CK_order_item_batches_qty CHECK (quantity_base > 0),
        CONSTRAINT CK_order_item_batches_type CHECK (movement_type IN (N'SALE', N'CUSTOMER_RETURN'))
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_order_item_batches_item')
    ALTER TABLE dbo.order_item_batches WITH CHECK ADD CONSTRAINT FK_order_item_batches_item FOREIGN KEY(order_item_id) REFERENCES dbo.order_items(order_item_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_order_item_batches_batch')
    ALTER TABLE dbo.order_item_batches WITH CHECK ADD CONSTRAINT FK_order_item_batches_batch FOREIGN KEY(batch_id) REFERENCES dbo.product_batches(batch_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_order_item_batches_source')
    ALTER TABLE dbo.order_item_batches WITH CHECK ADD CONSTRAINT FK_order_item_batches_source FOREIGN KEY(source_allocation_id) REFERENCES dbo.order_item_batches(allocation_id);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_order_item_batches_qty')
    ALTER TABLE dbo.order_item_batches WITH CHECK ADD CONSTRAINT CK_order_item_batches_qty CHECK(quantity_base>0);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_order_item_batches_type')
    ALTER TABLE dbo.order_item_batches WITH CHECK ADD CONSTRAINT CK_order_item_batches_type CHECK(movement_type IN(N'SALE',N'CUSTOMER_RETURN'));

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.order_item_batches') AND name = N'IX_order_item_batches_item')
    CREATE INDEX IX_order_item_batches_item ON dbo.order_item_batches(order_item_id, movement_type);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.order_item_batches') AND name = N'IX_order_item_batches_batch')
    CREATE INDEX IX_order_item_batches_batch ON dbo.order_item_batches(batch_id, movement_type) INCLUDE(quantity_base, source_allocation_id);

IF OBJECT_ID(N'dbo.purchase_return_detail_batches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_return_detail_batches
    (
        return_batch_id  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_purchase_return_detail_batches PRIMARY KEY,
        return_detail_id INT NOT NULL,
        batch_id         INT NOT NULL,
        quantity_base    DECIMAL(18,3) NOT NULL,
        unit_cost        DECIMAL(18,2) NOT NULL,
        created_at       DATETIME NOT NULL CONSTRAINT DF_purchase_return_detail_batches_created_at DEFAULT (GETDATE()),
        CONSTRAINT FK_purchase_return_detail_batches_detail FOREIGN KEY (return_detail_id) REFERENCES dbo.purchase_return_details(return_detail_id),
        CONSTRAINT FK_purchase_return_detail_batches_batch FOREIGN KEY (batch_id) REFERENCES dbo.product_batches(batch_id),
        CONSTRAINT CK_purchase_return_detail_batches_qty CHECK (quantity_base > 0)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_purchase_return_detail_batches_detail')
    ALTER TABLE dbo.purchase_return_detail_batches WITH CHECK ADD CONSTRAINT FK_purchase_return_detail_batches_detail FOREIGN KEY(return_detail_id) REFERENCES dbo.purchase_return_details(return_detail_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_purchase_return_detail_batches_batch')
    ALTER TABLE dbo.purchase_return_detail_batches WITH CHECK ADD CONSTRAINT FK_purchase_return_detail_batches_batch FOREIGN KEY(batch_id) REFERENCES dbo.product_batches(batch_id);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_purchase_return_detail_batches_qty')
    ALTER TABLE dbo.purchase_return_detail_batches WITH CHECK ADD CONSTRAINT CK_purchase_return_detail_batches_qty CHECK(quantity_base>0);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.purchase_return_detail_batches') AND name = N'IX_purchase_return_detail_batches_detail')
    CREATE INDEX IX_purchase_return_detail_batches_detail ON dbo.purchase_return_detail_batches(return_detail_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.purchase_return_detail_batches') AND name = N'IX_purchase_return_detail_batches_batch')
    CREATE INDEX IX_purchase_return_detail_batches_batch ON dbo.purchase_return_detail_batches(batch_id) INCLUDE(quantity_base);

IF OBJECT_ID(N'dbo.batch_inventory_movements', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.batch_inventory_movements
    (
        movement_id      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_batch_inventory_movements PRIMARY KEY,
        batch_id         INT NOT NULL,
        movement_type    NVARCHAR(40) NOT NULL,
        quantity_change  DECIMAL(18,3) NOT NULL,
        reference_type   NVARCHAR(40) NOT NULL,
        reference_id     INT NOT NULL,
        reference_line_id INT NULL,
        note             NVARCHAR(500) NULL,
        created_at       DATETIME NOT NULL CONSTRAINT DF_batch_inventory_movements_created_at DEFAULT (GETDATE()),
        CONSTRAINT FK_batch_inventory_movements_batch FOREIGN KEY (batch_id) REFERENCES dbo.product_batches(batch_id),
        CONSTRAINT CK_batch_inventory_movements_nonzero CHECK (quantity_change <> 0)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_batch_inventory_movements_batch')
    ALTER TABLE dbo.batch_inventory_movements WITH CHECK ADD CONSTRAINT FK_batch_inventory_movements_batch FOREIGN KEY(batch_id) REFERENCES dbo.product_batches(batch_id);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_batch_inventory_movements_nonzero')
    ALTER TABLE dbo.batch_inventory_movements WITH CHECK ADD CONSTRAINT CK_batch_inventory_movements_nonzero CHECK(quantity_change<>0);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.batch_inventory_movements') AND name = N'IX_batch_inventory_movements_batch_date')
    CREATE INDEX IX_batch_inventory_movements_batch_date ON dbo.batch_inventory_movements(batch_id, created_at, movement_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.batch_inventory_movements') AND name = N'IX_batch_inventory_movements_reference')
    CREATE INDEX IX_batch_inventory_movements_reference ON dbo.batch_inventory_movements(reference_type, reference_id, reference_line_id);

IF OBJECT_ID(N'dbo.repair_order_items', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.repair_part_batch_allocations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.repair_part_batch_allocations
    (
        repair_batch_allocation_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_repair_part_batch_allocations PRIMARY KEY,
        repair_item_id             INT NOT NULL,
        batch_id                   INT NOT NULL,
        quantity_base              DECIMAL(18,3) NOT NULL,
        unit_cost                  DECIMAL(18,2) NOT NULL,
        created_at                 DATETIME NOT NULL CONSTRAINT DF_repair_part_batch_allocations_created_at DEFAULT(GETDATE()),
        CONSTRAINT FK_repair_part_batch_allocations_item FOREIGN KEY(repair_item_id) REFERENCES dbo.repair_order_items(repair_item_id),
        CONSTRAINT FK_repair_part_batch_allocations_batch FOREIGN KEY(batch_id) REFERENCES dbo.product_batches(batch_id),
        CONSTRAINT CK_repair_part_batch_allocations_qty CHECK(quantity_base > 0)
    );
    CREATE INDEX IX_repair_part_batch_allocations_item ON dbo.repair_part_batch_allocations(repair_item_id);
    CREATE INDEX IX_repair_part_batch_allocations_batch ON dbo.repair_part_batch_allocations(batch_id) INCLUDE(quantity_base, unit_cost);
END;

COMMIT TRANSACTION;
