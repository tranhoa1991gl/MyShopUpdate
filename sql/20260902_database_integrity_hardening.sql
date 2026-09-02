/*
    HoaTran POS - Vá toàn vẹn dữ liệu ngày 02/09/2026.

    Mục tiêu:
      - Gắn khóa ngoại đúng cho import_details.variant_id.
      - Bổ sung khóa ngoại/index còn thiếu của phân bổ lô sửa chữa.
      - Ngăn phát sinh Serial/IMEI trùng và làm an toàn nghiệp vụ bán/xuất hủy Serial.
      - Sửa xóa vĩnh viễn hóa đơn, phiếu nhập theo đúng thứ tự khóa ngoại.

    Script idempotent và không tự xóa dữ liệu nghiệp vụ cũ.
    Nếu đã có Serial trùng, unique index được bỏ qua; các Store mới vẫn chặn
    không cho phát sinh thêm Serial trùng.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* 1. Khóa ngoại đúng cho cột biến thể nhập hàng đang được ứng dụng sử dụng. */
IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.import_details', N'variant_id') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_key_columns fkc
       INNER JOIN sys.columns c
           ON c.object_id = fkc.parent_object_id
          AND c.column_id = fkc.parent_column_id
       WHERE fkc.parent_object_id = OBJECT_ID(N'dbo.import_details')
         AND fkc.referenced_object_id = OBJECT_ID(N'dbo.product_variants')
         AND c.name = N'variant_id'
   )
BEGIN
    DECLARE @ImportVariantFk SYSNAME =
        CASE WHEN EXISTS
        (
            SELECT 1 FROM sys.foreign_keys
            WHERE parent_object_id = OBJECT_ID(N'dbo.import_details')
              AND name = N'FK_import_details_variant_id'
        )
        THEN N'FK_import_details_variant_id_v2'
        ELSE N'FK_import_details_variant_id' END;

    DECLARE @ImportVariantWithCheck NVARCHAR(20) =
        CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.import_details d
            LEFT JOIN dbo.product_variants v ON v.variant_id = d.variant_id
            WHERE d.variant_id IS NOT NULL AND v.variant_id IS NULL
        )
        THEN N'WITH NOCHECK' ELSE N'WITH CHECK' END;

    DECLARE @ImportVariantSql NVARCHAR(MAX) =
        N'ALTER TABLE dbo.import_details ' + @ImportVariantWithCheck +
        N' ADD CONSTRAINT ' + QUOTENAME(@ImportVariantFk) +
        N' FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);' +
        N' ALTER TABLE dbo.import_details CHECK CONSTRAINT ' + QUOTENAME(@ImportVariantFk) + N';';
    EXEC sys.sp_executesql @ImportVariantSql;
END;

IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.import_details', N'variant_id') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes i
       INNER JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
       INNER JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
       WHERE i.object_id=OBJECT_ID(N'dbo.import_details')
         AND ic.key_ordinal=1
         AND c.name=N'variant_id'
   )
    CREATE INDEX IX_import_details_variant_id ON dbo.import_details(variant_id);

/* 2. Hoàn thiện ràng buộc cho bảng phân bổ lô sửa chữa đã được tạo trước đây. */
IF OBJECT_ID(N'dbo.repair_part_batch_allocations', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.repair_order_items', N'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_key_columns fkc
       INNER JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id
       WHERE fkc.parent_object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations')
         AND fkc.referenced_object_id=OBJECT_ID(N'dbo.repair_order_items')
         AND c.name=N'repair_item_id'
   )
BEGIN
    DECLARE @RepairItemFk SYSNAME =
        CASE WHEN EXISTS
        (
            SELECT 1 FROM sys.foreign_keys
            WHERE parent_object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations')
              AND name=N'FK_repair_part_batch_allocations_item'
        )
        THEN N'FK_repair_part_batch_allocations_item_v2'
        ELSE N'FK_repair_part_batch_allocations_item' END;

    DECLARE @RepairItemWithCheck NVARCHAR(20) =
        CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.repair_part_batch_allocations a
            LEFT JOIN dbo.repair_order_items i ON i.repair_item_id=a.repair_item_id
            WHERE i.repair_item_id IS NULL
        )
        THEN N'WITH NOCHECK' ELSE N'WITH CHECK' END;

    DECLARE @RepairItemSql NVARCHAR(MAX) =
        N'ALTER TABLE dbo.repair_part_batch_allocations ' + @RepairItemWithCheck +
        N' ADD CONSTRAINT ' + QUOTENAME(@RepairItemFk) +
        N' FOREIGN KEY(repair_item_id) REFERENCES dbo.repair_order_items(repair_item_id);' +
        N' ALTER TABLE dbo.repair_part_batch_allocations CHECK CONSTRAINT ' + QUOTENAME(@RepairItemFk) + N';';
    EXEC sys.sp_executesql @RepairItemSql;
END;

IF OBJECT_ID(N'dbo.repair_part_batch_allocations', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.product_batches', N'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.foreign_key_columns fkc
       INNER JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id
       WHERE fkc.parent_object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations')
         AND fkc.referenced_object_id=OBJECT_ID(N'dbo.product_batches')
         AND c.name=N'batch_id'
   )
BEGIN
    DECLARE @RepairBatchFk SYSNAME =
        CASE WHEN EXISTS
        (
            SELECT 1 FROM sys.foreign_keys
            WHERE parent_object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations')
              AND name=N'FK_repair_part_batch_allocations_batch'
        )
        THEN N'FK_repair_part_batch_allocations_batch_v2'
        ELSE N'FK_repair_part_batch_allocations_batch' END;

    DECLARE @RepairBatchWithCheck NVARCHAR(20) =
        CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.repair_part_batch_allocations a
            LEFT JOIN dbo.product_batches b ON b.batch_id=a.batch_id
            WHERE b.batch_id IS NULL
        )
        THEN N'WITH NOCHECK' ELSE N'WITH CHECK' END;

    DECLARE @RepairBatchSql NVARCHAR(MAX) =
        N'ALTER TABLE dbo.repair_part_batch_allocations ' + @RepairBatchWithCheck +
        N' ADD CONSTRAINT ' + QUOTENAME(@RepairBatchFk) +
        N' FOREIGN KEY(batch_id) REFERENCES dbo.product_batches(batch_id);' +
        N' ALTER TABLE dbo.repair_part_batch_allocations CHECK CONSTRAINT ' + QUOTENAME(@RepairBatchFk) + N';';
    EXEC sys.sp_executesql @RepairBatchSql;
END;

IF OBJECT_ID(N'dbo.repair_part_batch_allocations', N'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1 FROM sys.indexes i
       INNER JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
       INNER JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
       WHERE i.object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations') AND ic.key_ordinal=1 AND c.name=N'repair_item_id'
   )
    CREATE INDEX IX_repair_part_batch_allocations_item ON dbo.repair_part_batch_allocations(repair_item_id);

IF OBJECT_ID(N'dbo.repair_part_batch_allocations', N'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1 FROM sys.indexes i
       INNER JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
       INNER JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
       WHERE i.object_id=OBJECT_ID(N'dbo.repair_part_batch_allocations') AND ic.key_ordinal=1 AND c.name=N'batch_id'
   )
    CREATE INDEX IX_repair_part_batch_allocations_batch ON dbo.repair_part_batch_allocations(batch_id);

/* 3. Tạo unique index khi dữ liệu Serial hiện tại đủ sạch, không sửa dữ liệu cũ. */
IF OBJECT_ID(N'dbo.product_serials', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.product_serials
        WHERE serial_number IS NOT NULL
        GROUP BY LTRIM(RTRIM(serial_number))
        HAVING COUNT(*) > 1
    )
    AND NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes i
        INNER JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
        INNER JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
        WHERE i.object_id=OBJECT_ID(N'dbo.product_serials')
          AND i.is_unique=1
          AND ic.key_ordinal=1
          AND c.name=N'serial_number'
    )
    BEGIN
        CREATE UNIQUE INDEX UX_product_serials_serial_number
            ON dbo.product_serials(serial_number)
            WHERE serial_number IS NOT NULL;
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.ProductSerials_Insert
    @product_id INT,
    @import_id INT,
    @serial_number NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');
    IF @serial_number IS NULL
        THROW 51160, N'Serial/IMEI không hợp lệ.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.product_serials WITH (UPDLOCK, HOLDLOCK)
            WHERE LTRIM(RTRIM(ISNULL(serial_number, N''))) = @serial_number
        )
            THROW 51161, N'Serial/IMEI đã tồn tại trong hệ thống.', 1;

        INSERT INTO dbo.product_serials(product_id, import_id, serial_number, status, created_at)
        VALUES(@product_id, @import_id, @serial_number, 0, GETDATE());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.ProductSerials_Sell
    @serial_number NVARCHAR(100),
    @order_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @serial_number = NULLIF(LTRIM(RTRIM(@serial_number)), N'');
    IF @serial_number IS NULL
        THROW 51160, N'Serial/IMEI không hợp lệ.', 1;

    IF EXISTS
    (
        SELECT 1 FROM dbo.product_serials
        WHERE LTRIM(RTRIM(ISNULL(serial_number, N'')))=@serial_number
          AND order_id=@order_id AND status=1
    )
        RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SerialId INT;
        SELECT TOP (1) @SerialId=serial_id
        FROM dbo.product_serials WITH (UPDLOCK, HOLDLOCK)
        WHERE LTRIM(RTRIM(ISNULL(serial_number, N'')))=@serial_number
          AND status=0
        ORDER BY serial_id;

        IF @SerialId IS NULL
            THROW 51162, N'Serial/IMEI đã được bán hoặc không còn trong kho.', 1;

        UPDATE dbo.product_serials
        SET order_id=@order_id, status=1
        WHERE serial_id=@SerialId AND status=0;

        IF @@ROWCOUNT <> 1
            THROW 51163, N'Không thể cập nhật trạng thái Serial/IMEI.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.ProductSerials_Scrap
    @SerialNumber NVARCHAR(100),
    @EmployeeId INT,
    @Reason NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @SerialNumber=NULLIF(LTRIM(RTRIM(@SerialNumber)),N'');
    IF @SerialNumber IS NULL
        THROW 51160, N'Serial/IMEI không hợp lệ.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SerialId INT, @ProductId INT, @CurrentStock DECIMAL(18,3);
        SELECT TOP (1) @SerialId=serial_id, @ProductId=product_id
        FROM dbo.product_serials WITH (UPDLOCK, HOLDLOCK)
        WHERE LTRIM(RTRIM(ISNULL(serial_number,N'')))=@SerialNumber
          AND status=0
        ORDER BY serial_id;

        IF @SerialId IS NULL
            THROW 51164, N'Serial/IMEI không tồn tại hoặc không còn trong kho.', 1;

        SELECT @CurrentStock=ISNULL(stock,0)
        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
        WHERE product_id=@ProductId;

        IF @CurrentStock IS NULL OR @CurrentStock < 1
            THROW 51165, N'Tồn kho không đủ để xuất hủy Serial/IMEI.', 1;

        UPDATE dbo.product_serials
        SET status=2
        WHERE serial_id=@SerialId AND status=0;

        IF @@ROWCOUNT <> 1
            THROW 51166, N'Không thể cập nhật Serial/IMEI xuất hủy.', 1;

        UPDATE dbo.products
        SET stock=ISNULL(stock,0)-1
        WHERE product_id=@ProductId;

        DECLARE @CheckCode VARCHAR(20), @Attempt INT=0;
        WHILE @Attempt < 10
        BEGIN
            SET @CheckCode='XH'+CONVERT(CHAR(8),GETDATE(),112)+
                REPLACE(CONVERT(CHAR(8),GETDATE(),108),':','')+
                LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),4);
            IF NOT EXISTS(SELECT 1 FROM dbo.inventory_checks WITH (UPDLOCK,HOLDLOCK) WHERE check_code=@CheckCode)
                BREAK;
            SET @Attempt=@Attempt+1;
        END;

        IF @Attempt >= 10
            THROW 51167, N'Không thể tạo mã phiếu xuất hủy duy nhất.', 1;

        INSERT INTO dbo.inventory_checks(check_code,check_date,employee_id,note)
        VALUES(@CheckCode,GETDATE(),@EmployeeId,N'Xuất hủy trực tiếp Serial: '+@SerialNumber);

        DECLARE @CheckId INT=CONVERT(INT,SCOPE_IDENTITY());
        INSERT INTO dbo.inventory_check_details(check_id,product_id,system_stock,actual_stock,difference,reason)
        VALUES(@CheckId,@ProductId,@CurrentStock,@CurrentStock-1,-1,@Reason);

        COMMIT TRANSACTION;
        SELECT 1 AS Result;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* 4. Xóa phiếu nhập an toàn, không làm đứt lịch sử lô/Serial/trả hàng. */
CREATE OR ALTER PROCEDURE dbo.Imports_Delete
    @ImportId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Status NVARCHAR(50);
        SELECT @Status=status FROM dbo.imports WITH (UPDLOCK,HOLDLOCK) WHERE import_id=@ImportId;

        IF @Status IS NULL
            THROW 51170, N'Không tìm thấy phiếu nhập cần xóa.', 1;
        IF @Status NOT IN (N'Pending',N'Cancelled')
            THROW 51171, N'Chỉ được xóa phiếu nhập tạm hoặc đã hủy.', 1;
        IF EXISTS(SELECT 1 FROM dbo.purchase_returns WITH (UPDLOCK,HOLDLOCK) WHERE import_id=@ImportId)
            THROW 51172, N'Không thể xóa phiếu nhập đã có lịch sử trả nhà cung cấp.', 1;
        IF EXISTS
        (
            SELECT 1 FROM dbo.product_serials WITH (UPDLOCK,HOLDLOCK)
            WHERE import_id=@ImportId AND (ISNULL(status,0)<>0 OR order_id IS NOT NULL)
        )
            THROW 51173, N'Không thể xóa phiếu nhập có Serial/IMEI đã phát sinh nghiệp vụ.', 1;
        IF EXISTS
        (
            SELECT 1 FROM dbo.order_item_batches a
            INNER JOIN dbo.product_batches b ON b.batch_id=a.batch_id
            INNER JOIN dbo.import_details d ON d.import_detail_id=b.import_detail_id
            WHERE d.import_id=@ImportId
        )
            THROW 51174, N'Không thể xóa phiếu nhập có lô đã xuất bán.', 1;
        IF EXISTS
        (
            SELECT 1 FROM dbo.purchase_return_detail_batches a
            INNER JOIN dbo.product_batches b ON b.batch_id=a.batch_id
            INNER JOIN dbo.import_details d ON d.import_detail_id=b.import_detail_id
            WHERE d.import_id=@ImportId
        )
            THROW 51175, N'Không thể xóa phiếu nhập có lô đã trả nhà cung cấp.', 1;
        IF OBJECT_ID(N'dbo.repair_part_batch_allocations',N'U') IS NOT NULL
           AND EXISTS
           (
               SELECT 1 FROM dbo.repair_part_batch_allocations a
               INNER JOIN dbo.product_batches b ON b.batch_id=a.batch_id
               INNER JOIN dbo.import_details d ON d.import_detail_id=b.import_detail_id
               WHERE d.import_id=@ImportId
           )
            THROW 51176, N'Không thể xóa phiếu nhập có lô đã dùng cho sửa chữa.', 1;

        IF OBJECT_ID(N'dbo.supplier_debt_discount_allocations',N'U') IS NOT NULL
            DELETE FROM dbo.supplier_debt_discount_allocations WHERE import_id=@ImportId;

        DELETE m
        FROM dbo.batch_inventory_movements m
        INNER JOIN dbo.product_batches b ON b.batch_id=m.batch_id
        INNER JOIN dbo.import_details d ON d.import_detail_id=b.import_detail_id
        WHERE d.import_id=@ImportId;

        DELETE b
        FROM dbo.product_batches b
        INNER JOIN dbo.import_details d ON d.import_detail_id=b.import_detail_id
        WHERE d.import_id=@ImportId;

        DELETE FROM dbo.product_serials WHERE import_id=@ImportId;
        DELETE FROM dbo.import_details WHERE import_id=@ImportId;
        DELETE FROM dbo.imports WHERE import_id=@ImportId;

        IF @@ROWCOUNT<>1
            THROW 51177, N'Không xóa được phiếu nhập.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* 5. Xóa hóa đơn an toàn với bảng lô, ví và phân bổ giảm công nợ. */
CREATE OR ALTER PROCEDURE dbo.Orders_Delete
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Status NVARCHAR(50), @OrderType NVARCHAR(20);
        SELECT @Status=status,@OrderType=order_type
        FROM dbo.orders WITH (UPDLOCK,HOLDLOCK)
        WHERE order_id=@OrderId;

        IF @Status IS NULL
            THROW 51140, N'Không tìm thấy hóa đơn cần xóa.', 1;
        IF UPPER(ISNULL(@OrderType,N''))=N'RETURN'
            THROW 51141, N'Không thể xóa vĩnh viễn phiếu trả hàng.', 1;
        IF @Status NOT IN (N'Pending',N'Cancelled')
            THROW 51142, N'Chỉ được xóa hóa đơn tạm tính hoặc đã hủy.', 1;
        IF EXISTS(SELECT 1 FROM dbo.orders WITH (UPDLOCK,HOLDLOCK) WHERE original_order_id=@OrderId)
            THROW 51143, N'Không thể xóa hóa đơn đã có lịch sử trả hàng.', 1;

        IF OBJECT_ID(N'dbo.order_item_batches',N'U') IS NOT NULL
        BEGIN
            DELETE a
            FROM dbo.order_item_batches a
            INNER JOIN dbo.order_items oi ON oi.order_item_id=a.order_item_id
            WHERE oi.order_id=@OrderId;
        END;

        UPDATE dbo.product_serials
        SET status=0,order_id=NULL
        WHERE order_id=@OrderId;

        IF OBJECT_ID(N'dbo.customer_debt_discount_allocations',N'U') IS NOT NULL
            DELETE FROM dbo.customer_debt_discount_allocations WHERE order_id=@OrderId;
        IF OBJECT_ID(N'dbo.customer_wallet_transactions',N'U') IS NOT NULL
            DELETE FROM dbo.customer_wallet_transactions WHERE order_id=@OrderId;

        DELETE FROM dbo.order_items WHERE order_id=@OrderId;
        DELETE FROM dbo.orders WHERE order_id=@OrderId;

        IF @@ROWCOUNT<>1
            THROW 51144, N'Không xóa được hóa đơn.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* 6. Store sao lưu cũ không còn ghi cứng tên ProHKD. */
CREATE OR ALTER PROCEDURE dbo.BackupDatabase
    @BackupPath NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DatabaseName SYSNAME=DB_NAME();
    DECLARE @Sql NVARCHAR(MAX)=
        N'BACKUP DATABASE '+QUOTENAME(@DatabaseName)+
        N' TO DISK=N'''+REPLACE(@BackupPath,N'''',N'''''')+
        N''' WITH INIT,CHECKSUM,NAME=N''Full Backup'';';
    EXEC(@Sql);
END;
GO

/*
    Restore phải chạy từ kết nối master. Chặn Store cũ để tránh khôi phục nhầm
    database ProHKD; giao diện HoaTran POS đã có luồng khôi phục đúng database.
*/
CREATE OR ALTER PROCEDURE dbo.RestoreDatabase
    @BackupPath NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51190, N'Hãy dùng chức năng Khôi phục dữ liệu trong HoaTran POS để khôi phục đúng database đang kết nối.', 1;
END;
GO
