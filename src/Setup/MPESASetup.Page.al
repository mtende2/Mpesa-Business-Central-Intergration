page 50100 "MPESA Setup"
{
    Caption = 'M-Pesa Setup';
    PageType = Card;
    SourceTable = "MPESA Setup";
    ApplicationArea = All;
    UsageCategory = Administration;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field(Environment; Rec.Environment)
                {
                    ToolTip = 'Specifies whether requests go to the Safaricom Daraja sandbox or production API.';
                }
                field("Business Short Code"; Rec."Business Short Code")
                {
                    ToolTip = 'Specifies the PayBill or Till short code that receives payments.';
                }
                field("Callback URL"; Rec."Callback URL")
                {
                    ToolTip = 'Specifies the public HTTPS URL of the relay that receives Daraja STK callbacks and forwards them to Business Central.';
                }
            }
            group(Credentials)
            {
                Caption = 'Daraja Credentials';
                field(ConsumerKeyField; ConsumerKey)
                {
                    Caption = 'Consumer Key';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Specifies the Daraja app consumer key. Stored in isolated storage, never in a table.';
                    trigger OnValidate()
                    begin
                        Rec.SetConsumerKey(ConsumerKey);
                    end;
                }
                field(ConsumerSecretField; ConsumerSecret)
                {
                    Caption = 'Consumer Secret';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Specifies the Daraja app consumer secret. Stored in isolated storage, never in a table.';
                    trigger OnValidate()
                    begin
                        Rec.SetConsumerSecret(ConsumerSecret);
                    end;
                }
                field(PasskeyField; Passkey)
                {
                    Caption = 'Lipa Na M-Pesa Passkey';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Specifies the Lipa Na M-Pesa Online passkey used to sign STK Push requests.';
                    trigger OnValidate()
                    begin
                        Rec.SetPasskey(Passkey);
                    end;
                }
            }
            group(Posting)
            {
                Caption = 'Posting';
                field("Bal. Account No."; Rec."Bal. Account No.")
                {
                    ToolTip = 'Specifies the bank account that represents the M-Pesa PayBill float.';
                }
                field("Payment Nos."; Rec."Payment Nos.")
                {
                    ToolTip = 'Specifies the number series used for posted M-Pesa payment documents.';
                }
                field("Auto Post Payments"; Rec."Auto Post Payments")
                {
                    ToolTip = 'Specifies whether the job queue posts matched payments automatically.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestConnection)
            {
                Caption = 'Test Connection';
                Image = TestDatabase;
                ToolTip = 'Requests an OAuth access token from Daraja to confirm the credentials work.';
                trigger OnAction()
                var
                    MpesaApiMgt: Codeunit "MPESA API Mgt.";
                begin
                    MpesaApiMgt.TestConnection();
                end;
            }
            action(CreateJobQueueEntry)
            {
                Caption = 'Create Auto-Post Job';
                Image = Job;
                ToolTip = 'Creates a recurring job queue entry that posts matched M-Pesa payments every 5 minutes.';
                trigger OnAction()
                var
                    MpesaPostingMgt: Codeunit "MPESA Posting Mgt.";
                begin
                    MpesaPostingMgt.CreateAutoPostJobQueueEntry();
                end;
            }
        }
        area(Navigation)
        {
            action(Transactions)
            {
                Caption = 'M-Pesa Transactions';
                Image = Payment;
                RunObject = page "MPESA Transactions";
                ToolTip = 'Opens the M-Pesa transaction log.';
            }
        }
        area(Promoted)
        {
            actionref(TestConnection_Promoted; TestConnection) { }
            actionref(CreateJobQueueEntry_Promoted; CreateJobQueueEntry) { }
            actionref(Transactions_Promoted; Transactions) { }
        }
    }

    var
        ConsumerKey: Text;
        ConsumerSecret: Text;
        Passkey: Text;
        StoredValueTxt: Label '********', Locked = true;

    trigger OnOpenPage()
    begin
        Rec.Reset();
        Rec.GetRecordOnce();
        if Rec.HasCredentials() then begin
            ConsumerKey := StoredValueTxt;
            ConsumerSecret := StoredValueTxt;
            Passkey := StoredValueTxt;
        end;
    end;
}
