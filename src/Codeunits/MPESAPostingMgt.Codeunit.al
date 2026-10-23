codeunit 50101 "MPESA Posting Mgt."
{
    Access = Public;
    Permissions = tabledata "MPESA Transaction" = rm;

    var
        NotReadyErr: Label 'Entry %1 cannot be posted because its status is %2. Only completed payments can be posted.', Comment = '%1 = entry no., %2 = status';
        UnmatchedErr: Label 'Entry %1 is not matched to a customer. Assign a customer first.', Comment = '%1 = entry no.';
        DescriptionTxt: Label 'M-Pesa %1 %2', Comment = '%1 = receipt no., %2 = phone no.';
        JobDescriptionTxt: Label 'Post matched M-Pesa payments';
        JobCreatedMsg: Label 'A job queue entry now posts matched M-Pesa payments every %1 minutes.', Comment = '%1 = minutes';

    procedure PostTransaction(var MpesaTransaction: Record "MPESA Transaction")
    var
        Setup: Record "MPESA Setup";
        SourceCodeSetup: Record "Source Code Setup";
        GenJournalLine: Record "Gen. Journal Line";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        NoSeries: Codeunit "No. Series";
        PostingDate: Date;
        DocumentNo: Code[20];
        IsHandled: Boolean;
    begin
        if MpesaTransaction.Status <> MpesaTransaction.Status::Completed then
            Error(NotReadyErr, MpesaTransaction."Entry No.", MpesaTransaction.Status);
        if MpesaTransaction."Customer No." = '' then
            Error(UnmatchedErr, MpesaTransaction."Entry No.");

        Setup.Get();
        Setup.TestSetupForPosting();
        SourceCodeSetup.Get();

        PostingDate := DT2Date(MpesaTransaction."Transaction Date");
        if PostingDate = 0D then
            PostingDate := WorkDate();
        DocumentNo := NoSeries.GetNextNo(Setup."Payment Nos.", PostingDate);

        GenJournalLine.Init();
        GenJournalLine."Posting Date" := PostingDate;
        GenJournalLine."Document Date" := PostingDate;
        GenJournalLine."Document Type" := GenJournalLine."Document Type"::Payment;
        GenJournalLine."Document No." := DocumentNo;
        GenJournalLine."External Document No." := MpesaTransaction."M-Pesa Receipt No.";
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Customer);
        GenJournalLine.Validate("Account No.", MpesaTransaction."Customer No.");
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"Bank Account");
        GenJournalLine.Validate("Bal. Account No.", Setup."Bal. Account No.");
        GenJournalLine.Validate(Amount, -MpesaTransaction.Amount);
        if MpesaTransaction."Document No." <> '' then begin
            GenJournalLine."Applies-to Doc. Type" := GenJournalLine."Applies-to Doc. Type"::Invoice;
            GenJournalLine."Applies-to Doc. No." := MpesaTransaction."Document No.";
        end;
        GenJournalLine.Description := CopyStr(
            StrSubstNo(DescriptionTxt, MpesaTransaction."M-Pesa Receipt No.", MpesaTransaction."Phone No."),
            1, MaxStrLen(GenJournalLine.Description));
        GenJournalLine."Source Code" := SourceCodeSetup."Cash Receipt Journal";
        GenJournalLine."System-Created Entry" := true;

        OnBeforePostMpesaPayment(GenJournalLine, MpesaTransaction, IsHandled);
        if not IsHandled then
            GenJnlPostLine.RunWithCheck(GenJournalLine);

        MpesaTransaction.Status := MpesaTransaction.Status::Posted;
        MpesaTransaction."Posted Document No." := DocumentNo;
        MpesaTransaction."Error Message" := '';
        MpesaTransaction.Modify(true);

        OnAfterPostMpesaPayment(MpesaTransaction, DocumentNo);
    end;

    procedure PostAllReady()
    var
        MpesaTransaction: Record "MPESA Transaction";
        EntryNos: List of [Integer];
        EntryNo: Integer;
    begin
        MpesaTransaction.SetCurrentKey(Status, "Transaction Date");
        MpesaTransaction.SetRange(Status, MpesaTransaction.Status::Completed);
        MpesaTransaction.SetFilter("Customer No.", '<>%1', '');
        if MpesaTransaction.FindSet() then
            repeat
                EntryNos.Add(MpesaTransaction."Entry No.");
            until MpesaTransaction.Next() = 0;

        // Each payment posts in its own transaction, so one bad payment never blocks the rest.
        foreach EntryNo in EntryNos do
            PostSingleSafely(EntryNo);
    end;

    local procedure PostSingleSafely(EntryNo: Integer)
    var
        MpesaTransaction: Record "MPESA Transaction";
    begin
        Commit();
        if not MpesaTransaction.Get(EntryNo) then
            exit;
        if Codeunit.Run(Codeunit::"MPESA Post Transaction", MpesaTransaction) then
            exit;

        if MpesaTransaction.Get(EntryNo) then begin
            MpesaTransaction.Status := MpesaTransaction.Status::Error;
            MpesaTransaction."Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(MpesaTransaction."Error Message"));
            MpesaTransaction.Modify();
        end;
        Commit();
    end;

    procedure CreateAutoPostJobQueueEntry()
    var
        JobQueueEntry: Record "Job Queue Entry";
        MinutesBetweenRuns: Integer;
    begin
        MinutesBetweenRuns := 5;
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Codeunit);
        JobQueueEntry.SetRange("Object ID to Run", Codeunit::"MPESA Auto Post Job");
        if not JobQueueEntry.FindFirst() then begin
            JobQueueEntry.Init();
            JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
            JobQueueEntry."Object ID to Run" := Codeunit::"MPESA Auto Post Job";
            JobQueueEntry.Description := JobDescriptionTxt;
            JobQueueEntry."Recurring Job" := true;
            JobQueueEntry."No. of Minutes between Runs" := MinutesBetweenRuns;
            JobQueueEntry."Run on Mondays" := true;
            JobQueueEntry."Run on Tuesdays" := true;
            JobQueueEntry."Run on Wednesdays" := true;
            JobQueueEntry."Run on Thursdays" := true;
            JobQueueEntry."Run on Fridays" := true;
            JobQueueEntry."Run on Saturdays" := true;
            JobQueueEntry."Run on Sundays" := true;
            JobQueueEntry."Maximum No. of Attempts to Run" := 3;
        end;
        Codeunit.Run(Codeunit::"Job Queue - Enqueue", JobQueueEntry);
        Message(JobCreatedMsg, MinutesBetweenRuns);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostMpesaPayment(var GenJournalLine: Record "Gen. Journal Line"; var MpesaTransaction: Record "MPESA Transaction"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostMpesaPayment(var MpesaTransaction: Record "MPESA Transaction"; DocumentNo: Code[20])
    begin
    end;
}
