INSERT INTO users (
        username,
        email,
        password_hash,
        full_name,
        role,
        is_active
    )
VALUES (
        'qms_admin',
        'qms_admin@test.com',
        '$2a$10$X7...',
        -- Hash for 'test@1234'
        'QMS Administrator',
        'admin',
        true
    );
-- curl.exe -X POST "http://localhost:3000/api/qms/external/checklists/5/items/upload-report" -H "X-API-Key: sitedafilesdata" -F "check_id=SYN-TL-001" -F "report_path=/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_top/bronze_v1/run2/dashboard/Synthesis_QMS.csv" -F "file=@C:\Users\ganga\OneDrive\Desktop\ASI-Dashboard\ASI-dashboard\Synthesis_QMS_test.csv"
-- {"success":true,"message":"Report uploaded and linked to checklist item successfully","data":{"checkItemId":5,"reportDataId":1,"status":"in_review","rows_count":6}}
-- =========================================================
-- curl -X POST "http://13.204.252.101/api/qms/external/checklists/5/items/upload-report" \
--   -H "X-API-Key: sitedafilesdata" \
--   -F "check_id=SYN-TL-001" \
--   -F "report_path=/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_top/bronze_v1/run2/dashboard/Synthesis_QMS.csv" \
--   -F "file=@/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_top/bronze_v1/run2/dashboard/Synthesis_QMS.csv"