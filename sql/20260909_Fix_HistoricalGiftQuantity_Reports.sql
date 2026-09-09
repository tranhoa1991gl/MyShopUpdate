/*
    HoaTran POS - sửa giá vốn/số lượng hàng tặng của hóa đơn lịch sử.

    Phạm vi:
      - Report_GetOverview
      - Report_GetCustomerProfitByCustomer
      - Customer_GetTop
      - Report_GetInventoryMovement

    Không cập nhật dữ liệu hóa đơn. Script chỉ thay nhánh dự phòng khi
    order_items.base_quantity IS NULL. Có thể chạy lại an toàn.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.order_items', N'gift_quantity') IS NULL
        THROW 51000, N'Thiếu cột dbo.order_items.gift_quantity. Hãy cập nhật cấu trúc dữ liệu trước.', 1;

    DECLARE @Replacement NVARCHAR(1000) =
        N'ISNULL(oi.base_quantity, CASE WHEN ISNULL(oi.quantity, 0) < 0 '
        + N'THEN ISNULL(oi.quantity, 0) - ISNULL(oi.gift_quantity, 0) '
        + N'ELSE ISNULL(oi.quantity, 0) + ISNULL(oi.gift_quantity, 0) END)';

    DECLARE @Targets TABLE
    (
        procedure_name SYSNAME NOT NULL PRIMARY KEY
    );

    INSERT INTO @Targets(procedure_name)
    VALUES
        (N'dbo.Report_GetOverview'),
        (N'dbo.Report_GetCustomerProfitByCustomer'),
        (N'dbo.Customer_GetTop'),
        (N'dbo.Report_GetInventoryMovement');

    DECLARE @ProcedureName SYSNAME;
    DECLARE @Definition NVARCHAR(MAX);
    DECLARE @ProcedureTokenPosition INT;
    DECLARE @Message NVARCHAR(2048);

    DECLARE ProcedureCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT procedure_name
        FROM @Targets
        ORDER BY procedure_name;

    OPEN ProcedureCursor;
    FETCH NEXT FROM ProcedureCursor INTO @ProcedureName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Definition = OBJECT_DEFINITION(OBJECT_ID(@ProcedureName, N'P'));

        IF @Definition IS NULL
        BEGIN
            SET @Message = N'Không tìm thấy stored procedure ' + @ProcedureName + N'.';
            THROW 51001, @Message, 1;
        END;

        IF CHARINDEX(N'ISNULL(oi.base_quantity, oi.quantity)', @Definition) > 0
           OR CHARINDEX(N'ISNULL(oi.base_quantity,oi.quantity)', @Definition) > 0
        BEGIN
            SET @Definition = REPLACE(
                @Definition,
                N'ISNULL(oi.base_quantity, oi.quantity)',
                @Replacement
            );
            SET @Definition = REPLACE(
                @Definition,
                N'ISNULL(oi.base_quantity,oi.quantity)',
                @Replacement
            );

            -- ALTER PROCEDURE phải là câu lệnh đầu tiên trong batch động.
            SET @ProcedureTokenPosition = CHARINDEX(N'PROCEDURE', UPPER(@Definition));
            IF @ProcedureTokenPosition <= 0
            BEGIN
                SET @Message = N'Không nhận diện được định nghĩa của ' + @ProcedureName + N'.';
                THROW 51002, @Message, 1;
            END;

            SET @Definition = N'ALTER ' + SUBSTRING(@Definition, @ProcedureTokenPosition, LEN(@Definition));
            EXEC sys.sp_executesql @Definition;
        END
        ELSE IF CHARINDEX(N'gift_quantity', @Definition) = 0
        BEGIN
            SET @Message = N'Định nghĩa ' + @ProcedureName
                + N' không khớp phiên bản dự kiến; không tự động thay để tránh ghi sai nghiệp vụ.';
            THROW 51003, @Message, 1;
        END;

        FETCH NEXT FROM ProcedureCursor INTO @ProcedureName;
    END;

    CLOSE ProcedureCursor;
    DEALLOCATE ProcedureCursor;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'ProcedureCursor') >= 0
        CLOSE ProcedureCursor;
    IF CURSOR_STATUS('local', 'ProcedureCursor') > -3
        DEALLOCATE ProcedureCursor;
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

PRINT N'Đã cập nhật báo cáo để tính cả giá vốn/số lượng hàng tặng của hóa đơn lịch sử.';
GO
