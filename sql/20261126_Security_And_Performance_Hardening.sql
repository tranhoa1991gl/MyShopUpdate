-- Applies to the current shop database. Installation never invokes Database_ResetData.
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

DECLARE @own bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
IF @own = 1 BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @lock int;
    EXEC @lock = sys.sp_getapplock @Resource=N'HoaTranPOS.SecurityAndPerformance.20261126',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=30000;
    IF @lock < 0 THROW 51260, N'Không thể khóa migration bảo mật.', 1;

    -- Widen before creating covering indexes. Preserve nullability and bound defaults.
    DECLARE @prices TABLE (table_name sysname, column_name sysname);
    INSERT @prices VALUES (N'products',N'sell_price'), (N'order_items',N'unit_price');
    DECLARE @table sysname, @column sysname, @qualified nvarchar(260), @sql nvarchar(max),
        @defaultName sysname, @defaultSql nvarchar(max), @nullable bit;
    WHILE EXISTS (SELECT 1 FROM @prices)
    BEGIN
        SELECT TOP (1) @table=table_name, @column=column_name FROM @prices ORDER BY table_name;
        SET @qualified=N'dbo.'+QUOTENAME(@table);
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@qualified) AND name=@column
            AND system_type_id IN (106,108) AND scale=2 AND precision<18)
        BEGIN
            SELECT @defaultName=d.name, @defaultSql=d.definition, @nullable=c.is_nullable FROM sys.columns c
            LEFT JOIN sys.default_constraints d ON c.default_object_id=d.object_id
            WHERE c.object_id=OBJECT_ID(@qualified) AND c.name=@column;
            SET @sql=CASE WHEN @defaultName IS NULL THEN N'' ELSE N'ALTER TABLE '+@qualified+
                N' DROP CONSTRAINT '+QUOTENAME(@defaultName)+N';' END
                +N'ALTER TABLE '+@qualified+N' ALTER COLUMN '+QUOTENAME(@column)+N' DECIMAL(18,2) '
                +CASE WHEN @nullable=1 THEN N'NULL;' ELSE N'NOT NULL;' END
                +CASE WHEN @defaultName IS NULL THEN N'' ELSE N'ALTER TABLE '+@qualified+
                N' ADD CONSTRAINT '+QUOTENAME(@defaultName)+N' DEFAULT '+@defaultSql+N' FOR '+QUOTENAME(@column)+N';' END;
            EXEC sys.sp_executesql @sql;
        END;
        DELETE FROM @prices WHERE table_name=@table AND column_name=@column;
    END;

    -- Older modules may not supply every optional INCLUDE column. Index the available ones.
    DECLARE @indexes TABLE (idx sysname PRIMARY KEY, tbl sysname, keys_sql nvarchar(200),
        first_key sysname, second_key sysname NULL, include_csv nvarchar(500) NULL, filter_sql nvarchar(200) NULL);
    INSERT @indexes VALUES
        (N'IX_orders_order_date_status', N'orders', N'order_date DESC, status', N'order_date', N'status', N'customer_id, employee_id, cashier_id, final_amount, paid_amount, order_type, order_code', NULL),
        (N'IX_orders_customer_id_status', N'orders', N'customer_id, status', N'customer_id', N'status', N'order_date, final_amount, paid_amount, order_type', NULL),
        (N'IX_orders_order_code', N'orders', N'order_code', N'order_code', NULL, NULL, NULL),
        (N'IX_orders_original_order_id', N'orders', N'original_order_id', N'original_order_id', NULL, NULL, N'original_order_id IS NOT NULL'),
        (N'IX_order_items_order_id', N'order_items', N'order_id', N'order_id', NULL, N'product_id, product_variant_id, quantity, base_quantity, gift_quantity, unit_price, cost_price', NULL),
        (N'IX_order_items_product_id', N'order_items', N'product_id, order_id', N'product_id', N'order_id', NULL, NULL),
        (N'IX_imports_import_date_status', N'imports', N'import_date DESC, status', N'import_date', N'status', N'supplier_id, final_amount, paid_amount, import_code', NULL),
        (N'IX_imports_supplier_id_status', N'imports', N'supplier_id, status', N'supplier_id', N'status', N'import_date, final_amount, paid_amount', NULL),
        (N'IX_import_details_import_id', N'import_details', N'import_id', N'import_id', NULL, N'product_id, variant_id, quantity, base_quantity, import_price, total', NULL),
        (N'IX_import_details_product_id', N'import_details', N'product_id, import_id', N'product_id', N'import_id', NULL, NULL),
        (N'IX_customer_payments_customer_date', N'customer_payments', N'customer_id, payment_date DESC', N'customer_id', N'payment_date', N'amount, payment_method', NULL),
        (N'IX_supplier_payments_supplier_date', N'supplier_payments', N'supplier_id, payment_date DESC', N'supplier_id', N'payment_date', N'amount, payment_method', NULL),
        (N'IX_cashbook_entries_active_date', N'cashbook_entries', N'is_deleted, entry_date DESC, entry_type', N'is_deleted', N'entry_date', N'amount, category_id, payment_method, reference_code', NULL),
        (N'IX_products_product_code', N'products', N'product_code', N'product_code', NULL, NULL, NULL),
        (N'IX_products_barcode', N'products', N'barcode', N'barcode', NULL, NULL, N'barcode IS NOT NULL AND barcode <> N'''''),
        (N'IX_customers_phone', N'customers', N'phone', N'phone', NULL, NULL, N'phone IS NOT NULL AND phone <> N''''');
    DECLARE @index sysname, @keys nvarchar(200), @first sysname, @second sysname,
        @include nvarchar(500), @filter nvarchar(200), @included nvarchar(max);
    WHILE EXISTS (SELECT 1 FROM @indexes)
    BEGIN
        SELECT TOP (1) @index=idx,@table=tbl,@keys=keys_sql,@first=first_key,@second=second_key,
            @include=include_csv,@filter=filter_sql FROM @indexes ORDER BY idx;
        SET @qualified=N'dbo.'+QUOTENAME(@table);
        IF COL_LENGTH(@qualified,@first) IS NOT NULL AND (@second IS NULL OR COL_LENGTH(@qualified,@second) IS NOT NULL)
            AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(@qualified) AND name=@index)
        BEGIN
            SELECT @included=STUFF((SELECT N','+QUOTENAME(c.name) FROM sys.columns c
                WHERE c.object_id=OBJECT_ID(@qualified)
                AND CHARINDEX(N','+c.name+N',', N','+REPLACE(@include,N' ',N'')+N',')>0
                ORDER BY c.column_id FOR XML PATH(''),TYPE).value('.', 'nvarchar(max)'),1,1,N'');
            SET @sql=N'CREATE NONCLUSTERED INDEX '+QUOTENAME(@index)+N' ON '+@qualified+N'('+@keys+N')'
                +COALESCE(N' INCLUDE ('+NULLIF(@included,N'')+N')',N'')+COALESCE(N' WHERE '+@filter,N'');
            EXEC sys.sp_executesql @sql;
        END;
        DELETE FROM @indexes WHERE idx=@index;
    END;

    IF COL_LENGTH(N'dbo.Users',N'Username') IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.Users') AND name=N'UX_Users_Username')
        EXEC sys.sp_executesql N'
            IF NOT EXISTS (SELECT LOWER(LTRIM(RTRIM(Username))) FROM dbo.Users WITH (TABLOCKX,HOLDLOCK)
                GROUP BY LOWER(LTRIM(RTRIM(Username))) HAVING COUNT_BIG(*)>1)
                CREATE UNIQUE NONCLUSTERED INDEX UX_Users_Username ON dbo.Users(Username);
            ELSE PRINT N''Giữ nguyên tài khoản trùng tên hiện có. Chưa tạo UX_Users_Username.'';';

    -- Targeted edits retain the installed procedure parameters, result sets and shop-specific extensions.
    -- A different source shape is reported and rolled back instead of replacing the entire procedure.
    DECLARE @patches TABLE (seq int IDENTITY PRIMARY KEY, proc_name sysname, old_text nvarchar(max), new_text nvarchar(max));
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Cashbook_Insert', N'SELECT @ResolvedCategoryName = category_name', N'SET XACT_ABORT ON;
    DECLARE @ownsHardeningTransaction bit = CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
    IF @ownsHardeningTransaction=1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION HTCashbookInsert;
    BEGIN TRY
        SELECT @ResolvedCategoryName = category_name');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Cashbook_Insert', N'SELECT
        entry_id AS EntryId', N'        IF @ownsHardeningTransaction=1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @ownsHardeningTransaction=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        ELSE IF @ownsHardeningTransaction=0 AND XACT_STATE()=1 ROLLBACK TRANSACTION HTCashbookInsert;
        THROW;
    END CATCH;
    SELECT
        entry_id AS EntryId');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Orders_Insert', N'INSERT INTO orders (', N'SET XACT_ABORT ON;
    DECLARE @ownsHardeningTransaction bit = CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
    IF @ownsHardeningTransaction=1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION HTOrdersInsert;
    BEGIN TRY
        INSERT INTO orders (');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Orders_Insert', N'SELECT @NewOrderId;', N'        IF @ownsHardeningTransaction=1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @ownsHardeningTransaction=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        ELSE IF @ownsHardeningTransaction=0 AND XACT_STATE()=1 ROLLBACK TRANSACTION HTOrdersInsert;
        THROW;
    END CATCH;
    SELECT @NewOrderId;');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'StoreInfo_Save', N'IF EXISTS (SELECT 1 FROM dbo.StoreInfo)', N'SET XACT_ABORT ON;
    DECLARE @ownsHardeningTransaction bit = CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
    IF @ownsHardeningTransaction=1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION HTStoreInfoSave;
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM dbo.StoreInfo WITH (UPDLOCK,HOLDLOCK))');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'StoreInfo_Save', NULL, N'        IF @ownsHardeningTransaction=1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @ownsHardeningTransaction=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        ELSE IF @ownsHardeningTransaction=0 AND XACT_STATE()=1 ROLLBACK TRANSACTION HTStoreInfoSave;
        THROW;
    END CATCH;
');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Users_Insert', N'IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username = @Username)', N'SET XACT_ABORT ON;
    DECLARE @ownsHardeningTransaction bit = CASE WHEN @@TRANCOUNT=0 THEN 1 ELSE 0 END;
    IF @ownsHardeningTransaction=1 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION HTUsersInsert;
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM dbo.Users WITH (UPDLOCK,HOLDLOCK) WHERE Username = @Username)');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Users_Insert', N'SELECT 1 FROM dbo.Users WHERE employee_id = @EmployeeId', N'SELECT 1 FROM dbo.Users WITH (UPDLOCK,HOLDLOCK) WHERE employee_id = @EmployeeId');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Users_Insert', N'RETURN 0;', N'GOTO FinishUserInsert;');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Users_Insert', NULL, N'    FinishUserInsert:
        IF @ownsHardeningTransaction=1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @ownsHardeningTransaction=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
        ELSE IF @ownsHardeningTransaction=0 AND XACT_STATE()=1 ROLLBACK TRANSACTION HTUsersInsert;
        THROW;
    END CATCH;
');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Orders_GetList', N'o.order_date BETWEEN @FromDate AND DATEADD(SECOND, -1, @NextDay)', N'o.order_date >= @FromDate AND o.order_date < @NextDay');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Report_GetOverview', N'o.order_date BETWEEN @StartDate AND @EndDate', N'o.order_date >= @CashbookStartDate AND o.order_date < @CashbookEndExclusive');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Report_GetOverview', N'order_date BETWEEN @StartDate AND @EndDate', N'order_date >= @CashbookStartDate AND order_date < @CashbookEndExclusive');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Report_GetOverview', N'import_date BETWEEN @StartDate AND @EndDate', N'import_date >= @CashbookStartDate AND import_date < @CashbookEndExclusive');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Report_GetOverview', N'return_date BETWEEN @StartDate AND @EndDate', N'return_date >= @CashbookStartDate AND return_date < @CashbookEndExclusive');
    INSERT @patches (proc_name,old_text,new_text) VALUES (N'Database_ResetData', N'BEGIN TRANSACTION', N'BEGIN TRANSACTION;
        -- Clear optional child modules before the original shop reset sequence.
        IF OBJECT_ID(N''dbo.repair_part_batch_allocations'', N''U'') IS NOT NULL DELETE FROM dbo.repair_part_batch_allocations;
        IF OBJECT_ID(N''dbo.repair_part_movements'', N''U'') IS NOT NULL DELETE FROM dbo.repair_part_movements;
        IF OBJECT_ID(N''dbo.repair_payments'', N''U'') IS NOT NULL DELETE FROM dbo.repair_payments;
        IF OBJECT_ID(N''dbo.repair_order_events'', N''U'') IS NOT NULL DELETE FROM dbo.repair_order_events;
        IF OBJECT_ID(N''dbo.pos_installment_audit'', N''U'') IS NOT NULL DELETE FROM dbo.pos_installment_audit;
        IF OBJECT_ID(N''dbo.pos_installment_receipts'', N''U'') IS NOT NULL DELETE FROM dbo.pos_installment_receipts;
        IF OBJECT_ID(N''dbo.pos_installment_contracts'', N''U'') IS NOT NULL DELETE FROM dbo.pos_installment_contracts;
        IF OBJECT_ID(N''dbo.order_item_batch_selections'', N''U'') IS NOT NULL DELETE FROM dbo.order_item_batch_selections;
        IF OBJECT_ID(N''dbo.order_item_batches'', N''U'') IS NOT NULL DELETE FROM dbo.order_item_batches;
        IF OBJECT_ID(N''dbo.order_item_combo_snapshots'', N''U'') IS NOT NULL DELETE FROM dbo.order_item_combo_snapshots;
        IF OBJECT_ID(N''dbo.order_delivery_reservations'', N''U'') IS NOT NULL DELETE FROM dbo.order_delivery_reservations;
        IF OBJECT_ID(N''dbo.order_stock_movements'', N''U'') IS NOT NULL DELETE FROM dbo.order_stock_movements;
        IF OBJECT_ID(N''dbo.order_payment_splits'', N''U'') IS NOT NULL DELETE FROM dbo.order_payment_splits;
        IF OBJECT_ID(N''dbo.SaleQrPayment'', N''U'') IS NOT NULL DELETE FROM dbo.SaleQrPayment;
        IF OBJECT_ID(N''dbo.qr_payment_resolutions'', N''U'') IS NOT NULL DELETE FROM dbo.qr_payment_resolutions;
        IF OBJECT_ID(N''dbo.QrBankReferenceClaim'', N''U'') IS NOT NULL DELETE FROM dbo.QrBankReferenceClaim;
        IF OBJECT_ID(N''dbo.batch_inventory_movements'', N''U'') IS NOT NULL DELETE FROM dbo.batch_inventory_movements;
        IF OBJECT_ID(N''dbo.purchase_return_detail_batches'', N''U'') IS NOT NULL DELETE FROM dbo.purchase_return_detail_batches;
        IF OBJECT_ID(N''dbo.purchase_return_serials'', N''U'') IS NOT NULL DELETE FROM dbo.purchase_return_serials;
        IF OBJECT_ID(N''dbo.stock_export_details'', N''U'') IS NOT NULL DELETE FROM dbo.stock_export_details;
        IF OBJECT_ID(N''dbo.stock_exports'', N''U'') IS NOT NULL DELETE FROM dbo.stock_exports;
        IF OBJECT_ID(N''dbo.manufacturing_stock_movements'', N''U'') IS NOT NULL DELETE FROM dbo.manufacturing_stock_movements;
        IF OBJECT_ID(N''dbo.manufacturing_order_details'', N''U'') IS NOT NULL DELETE FROM dbo.manufacturing_order_details;
        IF OBJECT_ID(N''dbo.manufacturing_orders'', N''U'') IS NOT NULL DELETE FROM dbo.manufacturing_orders;
        IF OBJECT_ID(N''dbo.product_bom_items'', N''U'') IS NOT NULL DELETE FROM dbo.product_bom_items;
        IF OBJECT_ID(N''dbo.product_combo_variant_items'', N''U'') IS NOT NULL DELETE FROM dbo.product_combo_variant_items;
        IF OBJECT_ID(N''dbo.product_combo_items'', N''U'') IS NOT NULL DELETE FROM dbo.product_combo_items;
        IF OBJECT_ID(N''dbo.customer_debt_discount_allocations'', N''U'') IS NOT NULL DELETE FROM dbo.customer_debt_discount_allocations;
        IF OBJECT_ID(N''dbo.customer_debt_adjustments'', N''U'') IS NOT NULL DELETE FROM dbo.customer_debt_adjustments;
        IF OBJECT_ID(N''dbo.supplier_debt_discount_allocations'', N''U'') IS NOT NULL DELETE FROM dbo.supplier_debt_discount_allocations;
        IF OBJECT_ID(N''dbo.supplier_debt_adjustments'', N''U'') IS NOT NULL DELETE FROM dbo.supplier_debt_adjustments;
        IF OBJECT_ID(N''dbo.employee_payroll_payments'', N''U'') IS NOT NULL DELETE FROM dbo.employee_payroll_payments;
        IF OBJECT_ID(N''dbo.employee_payroll_adjustments'', N''U'') IS NOT NULL DELETE FROM dbo.employee_payroll_adjustments;
        IF OBJECT_ID(N''dbo.employee_payrolls'', N''U'') IS NOT NULL DELETE FROM dbo.employee_payrolls;
        IF OBJECT_ID(N''dbo.employee_payroll_settings'', N''U'') IS NOT NULL DELETE FROM dbo.employee_payroll_settings;
        IF OBJECT_ID(N''dbo.work_shift_bank_accounts'', N''U'') IS NOT NULL DELETE FROM dbo.work_shift_bank_accounts;
        IF OBJECT_ID(N''dbo.work_shifts'', N''U'') IS NOT NULL DELETE FROM dbo.work_shifts;
        IF OBJECT_ID(N''dbo.cashbook_entries'', N''U'') IS NOT NULL DELETE FROM dbo.cashbook_entries;
        IF OBJECT_ID(N''dbo.purchase_stock_history'', N''U'') IS NOT NULL DELETE FROM dbo.purchase_stock_history;
        IF OBJECT_ID(N''dbo.product_serial_status_correction_audit'', N''U'') IS NOT NULL DELETE FROM dbo.product_serial_status_correction_audit;
        IF OBJECT_ID(N''dbo.product_variant_stock_reclassification_audit'', N''U'') IS NOT NULL DELETE FROM dbo.product_variant_stock_reclassification_audit;
        IF OBJECT_ID(N''dbo.pos_ext_contacts'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_contacts;
        IF OBJECT_ID(N''dbo.pos_ext_promotions'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_promotions;
        IF OBJECT_ID(N''dbo.pos_ops_stock_policy'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ops_stock_policy;
        IF OBJECT_ID(N''dbo.pos_ext_receipt_lines'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_receipt_lines;
        IF OBJECT_ID(N''dbo.pos_ext_receipts'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_receipts;
        IF OBJECT_ID(N''dbo.pos_ext_cart_commits'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_cart_commits;
        IF OBJECT_ID(N''dbo.pos_ext_exchanges'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ext_exchanges;
        IF OBJECT_ID(N''dbo.pos_ops_debt_terms'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ops_debt_terms;
        IF OBJECT_ID(N''dbo.pos_ops_debt_contacts'', N''U'') IS NOT NULL DELETE FROM dbo.pos_ops_debt_contacts;
        IF OBJECT_ID(N''dbo.loyalty_point_rules'', N''U'') IS NOT NULL DELETE FROM dbo.loyalty_point_rules;
        IF OBJECT_ID(N''dbo.customer_wallet_transactions'', N''U'') IS NOT NULL DELETE FROM dbo.customer_wallet_transactions;
        IF OBJECT_ID(N''dbo.product_serials'', N''U'') IS NOT NULL DELETE FROM dbo.product_serials;
        IF OBJECT_ID(N''dbo.repair_order_items'', N''U'') IS NOT NULL DELETE FROM dbo.repair_order_items;
        IF OBJECT_ID(N''dbo.repair_orders'', N''U'') IS NOT NULL DELETE FROM dbo.repair_orders;
        IF OBJECT_ID(N''dbo.inventory_check_details'', N''U'') IS NOT NULL DELETE FROM dbo.inventory_check_details;
        IF OBJECT_ID(N''dbo.product_batches'', N''U'') IS NOT NULL DELETE FROM dbo.product_batches;');

    DECLARE @name sysname, @module nvarchar(max), @old nvarchar(max), @new nvarchar(max),
        @seq int, @end int, @msg nvarchar(2048);
    WHILE EXISTS (SELECT 1 FROM @patches)
    BEGIN
        SELECT TOP (1) @name=proc_name FROM @patches ORDER BY seq;
        SET @qualified=N'dbo.'+QUOTENAME(@name);
        SET @module=REPLACE(OBJECT_DEFINITION(OBJECT_ID(@qualified,N'P')),CHAR(13),N'');
        IF @module IS NULL AND OBJECT_ID(@qualified,N'P') IS NOT NULL
            THROW 51261, N'Không đọc được định nghĩa thủ tục để nâng cấp.', 1;
        IF @module IS NOT NULL AND CHARINDEX(N'/* HoaTranPOS 20261126 */',@module)=0
        BEGIN
            WHILE EXISTS (SELECT 1 FROM @patches WHERE proc_name=@name)
            BEGIN
                SELECT TOP (1) @seq=seq,@old=old_text,@new=REPLACE(new_text,CHAR(13),N'')
                    FROM @patches WHERE proc_name=@name ORDER BY seq;
                SET @old=REPLACE(@old,CHAR(13),N'');
                IF @old IS NULL
                BEGIN
                    SET @end=LEN(@module);
                    WHILE @end>0 AND SUBSTRING(@module,@end,1) IN (CHAR(10),CHAR(9),N' ',N';') SET @end-=1;
                    IF UPPER(SUBSTRING(@module,@end-2,3))<>N'END'
                        THROW 51262, N'Không nhận diện được cuối thủ tục.', 1;
                    SET @module=STUFF(@module,@end-2,0,@new);
                END
                ELSE IF CHARINDEX(LEFT(@old,4000),@module)=0
                BEGIN
                    SET @msg=N'Cấu trúc thủ tục '+@qualified+N' khác phiên bản hỗ trợ. Migration đã dừng để bảo toàn logic hiện tại.';
                    THROW 51263,@msg,1;
                END
                ELSE
                BEGIN
                    -- STUFF also handles the reset block, which exceeds REPLACE's pattern limit.
                    DECLARE @pos int = CHARINDEX(LEFT(@old,4000),@module);
                    WHILE @pos>0
                    BEGIN
                        IF SUBSTRING(@module,@pos,DATALENGTH(@old)/2) COLLATE Latin1_General_100_BIN2 <> @old COLLATE Latin1_General_100_BIN2
                            THROW 51264, N'Thân thủ tục đã được tùy chỉnh. Không ghi đè thay đổi.', 1;
                        SET @module=STUFF(@module,@pos,DATALENGTH(@old)/2,@new);
                        SET @pos=CHARINDEX(LEFT(@old,4000),@module,@pos+DATALENGTH(@new)/2);
                    END;
                END;
                DELETE FROM @patches WHERE seq=@seq;
            END;
            WHILE LEFT(@module,1) IN (CHAR(10),CHAR(9),N' ') SET @module=SUBSTRING(@module,2,2147483647);
            IF UPPER(LEFT(@module,15))=N'CREATE OR ALTER' SET @module=STUFF(@module,1,15,N'ALTER');
            ELSE IF UPPER(LEFT(@module,6))=N'CREATE' SET @module=STUFF(@module,1,6,N'ALTER');
            IF UPPER(LEFT(@module,5))<>N'ALTER' THROW 51265,N'Không nhận diện được khai báo thủ tục.',1;
            SET @module=STUFF(@module,6,0,N' /* HoaTranPOS 20261126 */');
            EXEC sys.sp_executesql @module;
        END;
        DELETE FROM @patches WHERE proc_name=@name;
    END;
    IF @own=1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @own=1 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
