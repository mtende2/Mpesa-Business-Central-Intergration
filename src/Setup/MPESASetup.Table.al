table 50100 "MPESA Setup"
{
    Caption = 'M-Pesa Setup';
    DataClassification = CustomerContent;
    DataPerCompany = true;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
        }
        field(10; Environment; Enum "MPESA Environment")
        {
            Caption = 'Environment';
        }
        field(20; "Business Short Code"; Code[20])
        {
            Caption = 'Business Short Code (PayBill)';
        }
        field(30; "Callback URL"; Text[250])
        {
            Caption = 'STK Callback URL';
            ExtendedDatatype = URL;
        }
        field(40; "Bal. Account No."; Code[20])
        {
            Caption = 'M-Pesa Bank Account No.';
            TableRelation = "Bank Account";
        }
        field(41; "Payment Nos."; Code[20])
        {
            Caption = 'Payment Nos.';
            TableRelation = "No. Series";
        }
        field(50; "Auto Post Payments"; Boolean)
        {
            Caption = 'Auto Post Payments';
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    var
        ConsumerKeyLbl: Label 'MPESA-ConsumerKey', Locked = true;
        ConsumerSecretLbl: Label 'MPESA-ConsumerSecret', Locked = true;
        PasskeyLbl: Label 'MPESA-Passkey', Locked = true;
        MissingSecretErr: Label 'The %1 has not been set. Enter it on the M-Pesa Setup page.', Comment = '%1 = credential name';

    procedure GetRecordOnce()
    begin
        if not Get() then begin
            Init();
            Insert();
        end;
    end;

    procedure GetBaseUrl(): Text
    begin
        case Environment of
            Environment::Sandbox:
                exit('https://sandbox.safaricom.co.ke');
            Environment::Production:
                exit('https://api.safaricom.co.ke');
        end;
    end;

    procedure TestSetupForStkPush()
    begin
        TestField("Business Short Code");
        TestField("Callback URL");
        GetConsumerKey();
        GetConsumerSecret();
        GetPasskey();
    end;

    procedure TestSetupForPosting()
    begin
        TestField("Bal. Account No.");
        TestField("Payment Nos.");
    end;

    procedure SetConsumerKey(Value: SecretText)
    begin
        SetSecret(ConsumerKeyLbl, Value);
    end;

    procedure GetConsumerKey(): SecretText
    begin
        exit(GetSecret(ConsumerKeyLbl, 'Consumer Key'));
    end;

    procedure SetConsumerSecret(Value: SecretText)
    begin
        SetSecret(ConsumerSecretLbl, Value);
    end;

    procedure GetConsumerSecret(): SecretText
    begin
        exit(GetSecret(ConsumerSecretLbl, 'Consumer Secret'));
    end;

    procedure SetPasskey(Value: SecretText)
    begin
        SetSecret(PasskeyLbl, Value);
    end;

    procedure GetPasskey(): SecretText
    begin
        exit(GetSecret(PasskeyLbl, 'Lipa Na M-Pesa Passkey'));
    end;

    procedure HasCredentials(): Boolean
    begin
        exit(
            IsolatedStorage.Contains(ConsumerKeyLbl, DataScope::Company) and
            IsolatedStorage.Contains(ConsumerSecretLbl, DataScope::Company) and
            IsolatedStorage.Contains(PasskeyLbl, DataScope::Company));
    end;

    local procedure SetSecret(StorageKey: Text; Value: SecretText)
    begin
        if IsolatedStorage.Contains(StorageKey, DataScope::Company) then
            IsolatedStorage.Delete(StorageKey, DataScope::Company);
        if not Value.IsEmpty() then
            IsolatedStorage.Set(StorageKey, Value, DataScope::Company);
    end;

    local procedure GetSecret(StorageKey: Text; DisplayName: Text) Value: SecretText
    begin
        if not IsolatedStorage.Get(StorageKey, DataScope::Company, Value) then
            Error(MissingSecretErr, DisplayName);
    end;
}
