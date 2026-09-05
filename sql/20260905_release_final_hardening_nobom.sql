/*
    MyShop - Release final hardening
    Date: 2026-09-05

    Mục tiêu:
      1) Chặn trùng Serial/IMEI ở tầng SQL.
      2) Chặn trùng cùng sản phẩm trong một phiếu kiểm kho.
      3) Chặn giá trị status Serial ngoài tập 0..4 (vẫn cho phép NULL để tương thích dữ liệu cũ).

    Lưu ý:
      - Chạy trên đúng database MyShop của khách hàng.
      - Script idempotent: có thể chạy lại.
      - Nếu phát hiện dữ liệu cũ bị trùng/sai status, script sẽ dừng và ROLLBACK thay vì tự đoán cách sửa.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 51320, N'Vui lòng chọn đúng database MyShop trước khi chạy migration.', 1;

IF OBJECT_ID(N'dbo.product_serials', N'U') IS NULL
    THROW 51321, N'Không tìm thấy bảng dbo.product_serials.', 1;

IF OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NULL
    THROW 51322, N'Không tìm thấy bảng dbo.inventory_check_details.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    ---------------------------------------------------------------------------
    -- 1. SERIAL / IMEI: chuẩn hóa khoảng trắng và tạo UNIQUE INDEX
    ---------------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM dbo.product_serials
        WHERE NULLIF(LTRIM(RTRIM(serial_number)), N'') IS NOT NULL
        GROUP BY LOWER(LTRIM(RTRIM(serial_number)))
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 51323,
            N'Không thể tạo UNIQUE Serial/IMEI: đang có Serial trùng sau khi chuẩn hóa. Hãy xử lý dữ liệu trùng trước.',
            1;
    END;

    UPDATE dbo.product_serials
    SET serial_number = NULLIF(LTRIM(RTRIM(serial_number)), N'')
    WHERE serial_number IS NOT NULL
      AND (serial_number <> LTRIM(RTRIM(serial_number))
           OR LTRIM(RTRIM(serial_number)) = N'');

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.product_serials')
          AND name = N'UX_product_serials_serial_number'
    )
    BEGIN
        CREATE UNIQUE INDEX UX_product_serials_serial_number
            ON dbo.product_serials(serial_number)
            WHERE serial_number IS NOT NULL;
    END;

    ---------------------------------------------------------------------------
    -- 2. KIỂM KHO: một sản phẩm chỉ có một detail trong cùng phiếu
    ---------------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM dbo.inventory_check_details
        WHERE check_id IS NULL OR product_id IS NULL
    )
    BEGIN
        THROW 51326,
            N'Không thể tạo UNIQUE kiểm kho: còn check_id/product_id NULL. Hãy chạy migration kiểm kho hardening trước.',
            1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.inventory_check_details
        GROUP BY check_id, product_id
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 51324,
            N'Không thể tạo UNIQUE kiểm kho: đang có (check_id, product_id) bị trùng. Hãy xử lý dữ liệu trùng trước.',
            1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.inventory_check_details')
          AND name = N'UX_inventory_check_details_check_product'
    )
    BEGIN
        CREATE UNIQUE INDEX UX_inventory_check_details_check_product
            ON dbo.inventory_check_details(check_id, product_id);
    END;

    ---------------------------------------------------------------------------
    -- 3. SERIAL STATUS: chỉ cho 0..4; giữ NULL để tương thích dữ liệu cũ
    --    0 Trong kho | 1 Đã bán | 2 Đang sửa chữa | 3 Đã trả NCC | 4 Đã xuất hủy
    ---------------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM dbo.product_serials
        WHERE status IS NOT NULL
          AND status NOT IN (0, 1, 2, 3, 4)
    )
    BEGIN
        THROW 51325,
            N'Không thể thêm CHECK Serial status: tồn tại status ngoài 0..4. Hãy xử lý dữ liệu sai trước.',
            1;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.product_serials')
          AND name = N'CK_product_serials_status'
    )
    BEGIN
        ALTER TABLE dbo.product_serials WITH CHECK
        ADD CONSTRAINT CK_product_serials_status
            CHECK (status IS NULL OR status IN (0, 1, 2, 3, 4));
    END;

    ALTER TABLE dbo.product_serials WITH CHECK
        CHECK CONSTRAINT CK_product_serials_status;

    COMMIT TRANSACTION;

    PRINT N'OK - Release final hardening đã được áp dụng thành công.';
    PRINT N'  + UX_product_serials_serial_number';
    PRINT N'  + UX_inventory_check_details_check_product';
    PRINT N'  + CK_product_serials_status';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
