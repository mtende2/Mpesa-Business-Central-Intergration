table 50101 "MPESA Transaction"
{
    Caption = 'M-Pesa Transaction';
    DataClassification = CustomerContent;
    LookupPageId = "MPESA Transactions";
    DrillDownPageId = "MPESA Transactions";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Transaction Type"; Enum "MPESA Trans. Type")
        {
            Caption = 'Transaction Type';
        }
        field(3; Status; Enum "MPESA Trans. Status")
        {
            Caption = 'Status';
        }
        field(10; "Phone No."; Text[20])
        {
            Caption = 'Phone No.';
            DataClassification = EndUserIdentifiableInformation;
        }
        field(11; Amount; Decimal)
        {
            Caption = 'Amount';
            AutoFormatType = 1;
            MinValue = 0;
        }
        field(12; "Account Reference"; Code[20])
        {
            Caption = 'Account Reference';
        }
        field(13; "Customer No."; Code[20])
        {
            Caption = 'Customer No.';
            TableRelation = Customer;

            trigger OnValidate()
            begin
                if Status = Status::Posted then
                    Error(PostedCannotChangeErr);
                if (Status = Status::Unmatched) and ("Customer No." <> '') then
                    Status := Status::Completed;
            end;
        }
        field(14; "Document No."; Code[20])
        {
            Caption = 'Applies-to Invoice No.';
            TableRelation = "Sales Invoice Header" where("Bill-to Customer No." = field("Customer No."));
        }
        field(20; "Merchant Request ID"; Text[50])
        {
            Caption = 'Merchant Request ID';
        }
        field(21; "Checkout Request ID"; Text[50])
        {
            Caption = 'Checkout Request ID';
        }
        field(22; "M-Pesa Receipt No."; Code[20])
        {
            Caption = 'M-Pesa Receipt No.';
        }
        field(23; "Transaction Date"; DateTime)
        {
            Caption = 'Transaction Date';
        }
        field(24; "Payer Name"; Text[100])
        {
            Caption = 'Payer Name';
            DataClassification = EndUserIdentifiableInformation;
        }
        field(25; "Result Code"; Integer)
        {
            Caption = 'Result Code';
        }
        field(26; "Result Description"; Text[250])
        {
            Caption = 'Result Description';
        }
        field(30; "Posted Document No."; Code[20])
        {
            Caption = 'Posted Document No.';
            Editable = false;
        }
        field(31; "Error Message"; Text[250])
        {
            Caption = 'Error Message';
            Editable = false;
        }
        field(40; "Customer Name"; Text[100])
        {
            Caption = 'Customer Name';
            FieldClass = FlowField;
            CalcFormula = lookup(Customer.Name where("No." = field("Customer No.")));
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Receipt; "M-Pesa Receipt No.") { }
        key(Checkout; "Checkout Request ID") { }
        key(StatusKey; Status, "Transaction Date") { }
    }

    var
        DuplicateReceiptErr: Label 'M-Pesa receipt %1 has already been recorded (entry %2).', Comment = '%1 = receipt no., %2 = entry no.';
        PostedCannotChangeErr: Label 'You cannot change a transaction that has already been posted.';

    procedure CheckDuplicateReceipt()
    var
        OtherTransaction: Record "MPESA Transaction";
    begin
        if "M-Pesa Receipt No." = '' then
            exit;
        OtherTransaction.SetCurrentKey("M-Pesa Receipt No.");
        OtherTransaction.SetRange("M-Pesa Receipt No.", "M-Pesa Receipt No.");
        OtherTransaction.SetFilter("Entry No.", '<>%1', "Entry No.");
        if OtherTransaction.FindFirst() then
            Error(DuplicateReceiptErr, "M-Pesa Receipt No.", OtherTransaction."Entry No.");
    end;

    procedure ReceiptAlreadyRecorded(ReceiptNo: Code[20]): Boolean
    var
        OtherTransaction: Record "MPESA Transaction";
    begin
        if ReceiptNo = '' then
            exit(false);
        OtherTransaction.SetCurrentKey("M-Pesa Receipt No.");
        OtherTransaction.SetRange("M-Pesa Receipt No.", ReceiptNo);
        exit(not OtherTransaction.IsEmpty());
    end;
}
