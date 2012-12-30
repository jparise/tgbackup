Program TelegardBackup;
{$F+,R+,I-,S+,D-}
{$M $4000,0,0 }
{---------------------------------------------------------------------------}
{                          .ùúGeneralúInformationúù.                        }
{---------------------------------------------------------------------------}
{

                                Telegard Backup
                            North Star Technologies
                       Copyright (c) 1996-97 Jon Parise
}

Uses Dos, Crt, nstAsm, nstStr, nstFile, nstTask, Inputs, Fader;

{$I Main.Pas}

{---------------------------------------------------------------------------}
{                         .ùúConstantúDeclarationsúù.                       }
{---------------------------------------------------------------------------}
Const
   Version      = '1.5';
   cfgVersion   = 14;
   Years        = '1996-97';
   ConfigName   = 'TgBackup.Cfg';
   MaxArchivers = 4;

{---------------------------------------------------------------------------}
{                           .ùúTypeúDeclarationsúù.                         }
{---------------------------------------------------------------------------}
Type
    tConfigRec = Record
     cfgVer           : Byte;
     TelegardPath     : String[80];    { Path to Telegard.Dat }
     BackupPath       : String[80];    { Path to create backups }
     UseDate          : Boolean;       { Include date in backup filename? }
     KeepDays         : Byte;          { Days to keep dated backups }
     Archiver         : Byte;          { Which archiver? }
     ArchiverPath     : String[80];    { Path to archivers }
     Fades            : Boolean;       { Use fades? }
     Main             : Boolean;       { Backup Main? }
     Data             : Boolean;       { Backup Data? }
     Files            : Boolean;       { Backup Files? }
     Lang             : Boolean;       { Backup Language? }
     Logs             : Boolean;       { Backup Logs? }
     Menu             : Boolean;       { Backup Menu? }
     Text             : Boolean;       { Backup Text? }
     Msgs             : Boolean;       { Backup Msgs? }
     Masks            : Array[1..8] of String[12]; { file masks }
     Extra1           : String[80];    { User Definable Path 1 }
     Extra2           : String[80];    { User Definable Path 2 }
    End; { tConfigRec}

    tArchiverRec = Record
     Name             : String[10];    { Name of archiver }
     Ext              : String[4];     { Extention of archiver }
     Filename         : String[12];    { Filename of archiver }
     Compress         : String[20];    { Compression commandline }
    End; { tArchiverRec }

    tScreenType = Array [0..3999] of Byte;

    tArchiverArray = Array [1..MaxArchivers] of tArchiverRec;

{$I Telegard.Inc}   { Telegard Type Definitions }

{---------------------------------------------------------------------------}
{                         .ùúVariableúDeclarationsúù.                       }
{---------------------------------------------------------------------------}
Var
   Screen      : tScreenType absolute $B800:0000;
   Config      : tConfigRec;     { Configuration }
   Telegard    : ConfigRec;      { Telegard.Dat }
   Archivers   : tArchiverArray; { Array of available archivers }
   Prefix      : String[8];      { Archive Prefix }
   C           : Char;           { Holds Charactor to Write }
   OrigPath    : String;         { Original Path }
   ArcName     : String[8];      { Override backup name }
   ArcType     : Byte;           { Override archiver type }

   { Date / Time Variables }
   Year        : Word;           { Year }
   Month       : Word;           { Month }
   Day         : Word;           { Day }
   DoW         : Word;           { Day of Week }
   Hour        : Word;           { Hour }
   Minute      : Word;           { Minute }
   Second      : Word;           { Second }
   Sec100      : Word;           { Sec100 }

{---------------------------------------------------------------------------}
{                         .ùúFunctionúDeclarationsúù.                       }
{---------------------------------------------------------------------------}

Function SearchExec (ProgName, Parameters : String) : Integer;
Var Result : Integer;

 Begin { SearchExec }

  { If the program doesn't exist then search on the %PATH for it }
  If Not fExist(ProgName) then ProgName := fSearch(ProgName,GetEnv('PATH'));

  { Now call the program...if it didn't exist the set DOSError to 2 }
  If ProgName <> '' then
     Begin
        SwapVectors;
        Exec(ProgName, Parameters);
        Result := DosError;
        SwapVectors;
        SearchExec := Result;
     End else SearchExec := 2;

 End;  { SearchExec }

{---------------------------------------------------------------------------}

Procedure Patch1; Interrupt;

 Begin { Patch1 }
  Write(C);
 End;  { Patch1 }

{---------------------------------------------------------------------------}

Procedure Patch; Assembler;

  Asm
     Push DS
     Push Ax
     Mov  AX, Seg C;
     Mov  DS, AX;
     Pop  AX;
     Mov  C, Al;
     Pop  DS
     Jmp  Patch1;
  End;  { Patch }

{---------------------------------------------------------------------------}

Function WindowExec (Archiver,Params,Path : String) : Integer;
Var
   Old_29h  : Pointer;
   CmdLine  : String[255];

 Begin { WindowExec }

  {$F+}
  GetIntVec($29, Old_29h);
  SetIntVec($29, @Patch);
  Window(11, 15, 68, 24);
  ClrScr;
  TextColor(DarkGray);
  CmdLine := Params + Path;
  WindowExec := SearchExec(Config.ArchiverPath + Archiver,CmdLine);
  SetIntVec($29, Old_29h);

 End;  { WindowExec }

{---------------------------------------------------------------------------}
{                         .ùúProcedureúDeclarationsúù.                      }
{---------------------------------------------------------------------------}

Procedure ProgInfo;

 Begin { ProgInfo }

  TextColor(11); Writeln('Telegard Backup v',Version);
  TextColor(03); Writeln('Copyright ',Years,' by Jon Parise. All rights reserved.');
  TextColor(08); Writeln('A North Star Technologies Software Release');

 End; { ProgInfo }

{---------------------------------------------------------------------------}

Procedure SetDefaults;
Var I : Byte;

 Begin { SetDefaults }

  With Config Do
    Begin
       cfgVer       := cfgVersion;
       TelegardPath := AddBackslash(GetEnv('TELEGARD'));
       If (not(DirExist(TelegardPath))) or (Length(TelegardPath) < 3) then
       TelegardPath := 'C:\Telegard\';
       BackupPath   := 'C:\TGBackup\';
       UseDate      := False;
       KeepDays     := 0;
       Archiver     := 1;
       ArchiverPath := TelegardPath + 'Archive\';
       Fades        := True;
       Main         := True;
       Data         := True;
       Files        := True;
       Lang         := True;
       Logs         := True;
       Menu         := True;
       Text         := True;
       Msgs         := True;
       For I := 1 to 8 do Masks[I] := '*.*';
       Extra1       := '';
       Extra2       := '';
     End;

 End;  { SetDefaults }

{---------------------------------------------------------------------------}

Procedure ReadTelegard;
Var
   ConfigFile : File of ConfigRec;
   TempStr    : String;
   Ignore     : Integer;

 Begin { ReadTelegard }

  {$I-}
  TempStr := Config.TelegardPath + 'Config.Tg';

  If Not fExist(TempStr) Then
     Begin
        Writeln; TextColor(LightCyan);
        Writeln ('        ',TempStr,' not found!');
        Writeln;
        Halt (1);
      End;
  Assign(ConfigFile,TempStr);
  Ignore := IoResult;
  Repeat
     Reset(ConfigFile);
     Ignore := IoResult;
     If Ignore = 5 Then Delay(300);
  Until Ignore <> 5;
  Read (ConfigFile,Telegard);
  Close (ConfigFile);
  {$I+}

 End;  { ReadTelegard }

{---------------------------------------------------------------------------}

Procedure ReadConfig (Filename : String);
Var
   ConfigFile : File of tConfigRec;
   Ignore     : Integer;

 Begin { ReadConfig }

  {$I-}
  If Not fExist(Filename) Then
     Begin
        Writeln; TextColor(LightCyan);
        Writeln ('        Configuration file not found!');
        Writeln; TextColor(White);
        Writeln ('        Run TGBACKUP -C to create one.');
        Writeln;
        Halt (1);
      End;
  Assign(ConfigFile,Filename);
  Ignore := IoResult;
  Repeat
     Reset(ConfigFile);
     Ignore := IoResult;
     If Ignore = 5 Then Delay(300);
  Until Ignore <> 5;
  Read (ConfigFile,Config);
  Close (ConfigFile);
  {$I+}

 End;  { ReadConfig }

{---------------------------------------------------------------------------}

Procedure WriteConfig (Filename : String);
Var
   ConfigFile : File of tConfigRec;
   Ignore     : Integer;

 Begin { WriteConfig }

  {$I-}
  Assign(ConfigFile,Filename);
  Ignore := IoResult;
  Repeat
     Rewrite(ConfigFile);
     Ignore := IoResult;
     If Ignore = 5 Then Delay(300);
  Until Ignore <> 5;
  Write(ConfigFile,Config);
  Close(ConfigFile);
  {$I+}

 End;  { WriteConfig }

{---------------------------------------------------------------------------}

Procedure Configuration;
Var
   I,J    : Integer;
   S      : String[25];
   C,C2   : Char;
   B      : Boolean;
   MaxItems : Integer;
   Status : Byte;
   Err    : Integer;
   InStr  : String[50];

 Begin { Configuration }

  If fExist(ConfigName) then ReadConfig(ConfigName) else SetDefaults;

  ClrScr; CursorOff;
  Move (Main,Screen,4000);
  GotoXY (43,3); TextColor(DarkGray); Write(Version);

  GotoXY (28,7);  S := 'C O N F I G U R A T I O N';
  For I := 1 to 25 do
      Begin
         Case I of
            1.. 4: TextColor (DarkGray);
            5.. 9: TextColor (LightGray);
           10..15: TextColor (White);
           15..21: TextColor (LightGray);
           22..25: TextColor (DarkGray);
          End; { Case }
         Write (S[I]);
      End;

  B := False;
  I := 1;
  MaxItems := 26;

  Repeat
     CursorOff;
     If I = 18 then I := 6;
     For J := 1 to MaxItems do
         Begin
            If J <= 16 then GotoXY(13,J+8) else GotoXY(44,J-4);
            If J = I then TextColor(White) else TextColor(DarkGray);
            Case J of
               1: Write('Telegard Path:');
               2: Write('  Backup Path:');
               3: Write('Archiver Path:');
               4: Write('     Archiver:');
               5: Write('Dated Backups:');
               6: Write(' Screen Fades:');
               7: Write('  Backup Main:');
               8: Write('  Backup Data:');
               9: Write('  Backup File:');
              10: Write('  Backup Lang:');
              11: Write('  Backup Logs:');
              12: Write('  Backup Menu:');
              13: Write('  Backup Text:');
              14: Write('  Backup Msgs:');
              15: Write(' Extra Path 1:');
              16: Write(' Extra Path 2:');
              { Second column }
              17: Write('Days to Keep:');
              18: ; { blank }
              19..26: Write('Mask:');
             End; { Case }
            If J <= 16 then GotoXY(29,J+8) else GotoXY(59,J-4);
            TextColor(Cyan);
            Case J of
               1: Write(Config.TelegardPath);
               2: Write(Config.BackupPath);
               3: Write(Config.ArchiverPath);
               4: Write(Archivers[(Config.Archiver)].Name);
               5: If Config.UseDate then Write('Enabled ') else Write('Disabled');
               6: If Config.Fades then Write('Enabled ') else Write('Disabled');
               7: If Config.Main then Write('Enabled ') else Write('Disabled');
               8: If Config.Data then Write('Enabled ') else Write('Disabled');
               9: If Config.Files then Write('Enabled ') else Write('Disabled');
              10: If Config.Lang then Write('Enabled ') else Write('Disabled');
              11: If Config.Logs then Write('Enabled ') else Write('Disabled');
              12: If Config.Menu then Write('Enabled ') else Write('Disabled');
              13: If Config.Text then Write('Enabled ') else Write('Disabled');
              14: If Config.Msgs then Write('Enabled ') else Write('Disabled');
              15: Write(Config.Extra1);
              16: Write(Config.Extra2);
              { Second column }
              17: If Config.KeepDays = 0 then Write('Disabled') else Write(Config.KeepDays,'       ');
              18: ; { blank }
              19..26: Begin
                        GotoXY(51,WhereY);
                        Write(Config.Masks[J-18]);
                      End;
             End; { Case }
         End;

     C := ReadKey;
     Case C of
       #27: B := True;                    { Escape     }
       #73: I := 1;                       { Home       }
       #81: I := MaxItems;                { End        }
       #71: I := 1;                       { Page Up    }
       #75: If (I >= 17) and (I <= 26)    { Right Arrow}
              then I := I - 12;
       #77: If (I >= 5) and (I <= 14)     { Left Arrow }
              then I := I + 12;
       #79: I := MaxItems;                { Page Down  }
       #72: If I > 1 then Dec(I);         { Up Arrow   }
       #80: If I < MaxItems then Inc(I);  { Down Arrow }
       ' ',                               { Space      }
       #13: Begin                         { Enter      }
               TextColor(LightCyan);
               Case I of
                  1: Begin
                       InStr := Input(29,9,Config.TelegardPath,' ','',39,-1,[#32..#175],True,Status);
                       If Status <> 27 then Config.TelegardPath := AddBackslash(InStr);
                     End;
                  2: Begin
                       InStr := Input(29,10,Config.BackupPath,' ','',39,-1,[#32..#175],True,Status);
                       If Status <> 27 then Config.BackupPath := AddBackslash(InStr);
                     End;
                  3: Begin
                       InStr := Input(29,11,Config.ArchiverPath,' ','',39,-1,[#32..#175],True,Status);
                       If Status <> 27 then Config.ArchiverPath := AddBackslash(InStr);
                     End;
                  4: If Config.Archiver < MaxArchivers then Inc(Config.Archiver)
                        else Config.Archiver := 1;
                  5: Config.UseDate := Not(Config.UseDate);
                  6: Config.Fades := Not(Config.Fades);
                  7: Config.Main := Not(Config.Main);
                  8: Config.Data := Not(Config.Data);
                  9: Config.Files := Not(Config.Files);
                 10: Config.Lang := Not(Config.Lang);
                 11: Config.Logs := Not(Config.Logs);
                 12: Config.Menu := Not(Config.Menu);
                 13: Config.Text := Not(Config.Text);
                 14: Config.Msgs := Not(Config.Msgs);
                 15: Begin
                       InStr := Input(29,23,Config.Extra1,' ','',39,-1,[#32..#175],True,Status);
                       If Status <> 27 then Config.Extra1 := AddBackslash(InStr);
                     End;
                 16: Begin
                       InStr := Input(29,24,Config.Extra2,' ','',39,-1,[#32..#175],True,Status);
                       If Status <> 27 then Config.Extra2 := AddBackslash(InStr);
                     End;
                 17: Begin
                       GotoXY(59,13); Write('        ');
                       Str(Config.KeepDays,InStr);
                       InStr := Input(59,13,InStr,' ','',3,-1,[#48..#57],True,Status);
                       If Status <> 27 then Val(InStr,Config.KeepDays,Err);
                       If Config.KeepDays > 30 then Config.KeepDays := 30;
                     End;
                 18: ; { blank }
                 19..26: Begin
                           InStr := Input(51,I-4,Config.Masks[I-18],' ','',12,-1,[#32..#175],True,Status);
                           If Status <> 27 then Config.Masks[I-18] := InStr;
                         End;
                End; { Case }
            End;
      End; { Case }
  Until B;

  GotoXY(26,25);
  TextColor(LightGray); Write('Save this configuration?'); TextColor(White);
  B := True;
  Repeat
     GotoXY (52,25);
     If B then Write('Yes') else Write('No ');
     C := ReadKey;
     Case Upcase(C) of
       'N': B := False;
       'Y': B := True;
       ' ': B := Not(B);
      End; { Case }
  Until C = #13;
  If B Then WriteConfig(ConfigName);
  CursorOn;
  Halt(0);

 End;  { Configuration }

{---------------------------------------------------------------------------}

Procedure DefineArchivers (Var Archivers : tArchiverArray);

 Begin { DefineArchivers }

  With Archivers[1] Do
    Begin
      Name     := 'Zip       ';
      Ext      := 'Zip ';
      Filename := 'PkZip.Exe';
      Compress := '-ex';
    End;

  With Archivers[2] Do
    Begin
      Name     := 'Arj       ';
      Ext      := 'Arj ';
      Filename := 'Arj.Exe';
      Compress := 'a -e';
    End;

  With Archivers[3] Do
    Begin
      Name     := 'Lha       ';
      Ext      := 'Lzh ';
      Filename := 'Lha.Exe';
      Compress := 'a';
    End;

  With Archivers[4] Do
    Begin
      Name     := 'Rar       ';
      Ext      := 'Rar ';
      Filename := 'Rar.Exe';
      Compress := 'a -m5';
    End;

 End;  { DefineArchivers }

{---------------------------------------------------------------------------}

Procedure MakePath (Path : String);
Var
   Try    : Byte;
   Slash  : Byte;
   Error  : Word;
   TmpDir : String;
   IncDir : String;
   NewDir : String;
   OurDir : String;

 Begin { MakePath }

  NewDir := Path;
  GetDir(0, OurDir);
  While NewDir[Length (NewDir)] = '\' Do Dec (NewDir[0]);
  IncDir := '';
  Repeat
     Slash := Pos('\', NewDir);
     If (Slash <> 0) Then
        Begin
          IncDir := IncDir + Copy(NewDir, 1, Slash);
          NewDir := Copy(NewDir, Slash + 1, Length(NewDir) - Slash);
        End
        Else IncDir := IncDir + NewDir;
     TmpDir := IncDir;
     If Length(TmpDir) > 3 Then
        While TmpDir[Length(TmpDir)] = '\' Do Dec (TmpDir[0]);
     Repeat
        {$I-} ChDir(TmpDir); {$I+}
        Error := IoResult;
        If (Error <> 0) Then
           Begin
             {$I-} MkDir(TmpDir); {$I+}
             Error := IoResult;
           End;
        If (Error <> 0) Then Inc(Try) Else Try := 0;
      Until (Error = 0) or (Try > 3);
  Until (Slash = 0) or (Error <> 0);
  ChDir(OurDir);

 End;  { MakePath }

{---------------------------------------------------------------------------}

Procedure DrawHeader;
Var TempStr : String[8];

 Begin { DrawHeader }

  GetDate(Year, Month, Day, DoW);
  If ArcName <> '' then Prefix := ArcName else
  If Config.UseDate then
     Begin
        Prefix := 'TGB-';
        Str(Month, TempStr);
        If Month < 10 then Prefix := Prefix + '0' + TempStr
                      else Prefix := Prefix + TempStr;
        Str(Day, TempStr);
        If Day < 10 then Prefix := Prefix + '0' + TempStr
                    else Prefix := Prefix + TempStr;
     End else Prefix := 'TGBackup';

  TextColor(DarkGray);
  GotoXY(13,7); Write('ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ--ú[          ]ú-ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
  GotoXY(13,8); Write('³                                                    ³');
  GotoXY(13,9); Write('³                                                    ³');
  GotoXY(13,10);Write('³                                                    ³');
  GotoXY(13,11);Write('³                                                    ³');
  GotoXY(13,12);Write('³                                                    ³');
  GotoXY(13,13);Write('³                                                    ³');
  GotoXY(13,14);Write('ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ--ú[          ]ú-ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');

  TextColor(White);
  GotoXY(36,7);  Write('Progress');
  GotoXY(36,14); Write('Activity');

  TextColor(Cyan);
  GotoXY(19,8);  Write('Main Directory');
  GotoXY(19,9);  Write('Data Directory');
  GotoXY(19,10); Write('File Directory');
  GotoXY(19,11); Write('Lang Directory');
  GotoXY(19,12); Write('Logs Directory');
  GotoXY(48,8);  Write('Menu Directory');
  GotoXY(48,9);  Write('Text Directory');
  GotoXY(48,10); Write('Message Directory');
  GotoXY(48,11); Write('Extra Directory 1');
  GotoXY(48,12); Write('Extra Directory 2');
  GotoXY(30,13); Write('Archiving ',Prefix + '.' + Archivers[Config.Archiver].Ext);

 End;  { DrawHeader }

{---------------------------------------------------------------------------}

Procedure Progress (Which  : Byte; Status : Byte);

 Begin { Progress }

  TextColor (LightCyan);
  Window (1,1,80,25);

  Case Which of
    1: GotoXY(17,8);
    2: GotoXY(17,9);
    3: GotoXY(17,10);
    4: GotoXY(17,11);
    5: GotoXY(17,12);

    6: GotoXY(46,8);
    7: GotoXY(46,9);
    8: GotoXY(46,10);
    9: GotoXY(46,11);
   10: GotoXY(46,12);

   11: GotoXY(28,13);
   End; { Case }

  Case Status of
    1: Begin
         TextColor(LightCyan + Blink); Write ('ù');
       End;
    2: Write ('û');
    3: Write ('-');
   End; { Case }

 End;  { Progress }

{---------------------------------------------------------------------------}

Procedure Backup (Var Config : tConfigRec;
                  Var Telegard : ConfigRec;
                  Var Archivers : tArchiverArray);
Var
   Archiver : String[12];
   Params   : String[120];
   Path     : String[120];
   Dest     : String[120];

 Begin { Backup }

  If Not DirExist(Config.BackupPath) then MakePath(Config.BackupPath);
  Archiver := Archivers[Config.Archiver].Filename;
  Dest     := Archivers[Config.Archiver].Compress;

  { Backup Main Directory }
  If Config.Main Then
     Begin
       Progress(1,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Main.' +
                   Archivers[Config.Archiver].Ext;
       Path := Config.TelegardPath + Config.Masks[1];
       WindowExec(Archiver,Params,Path);
       Progress(1,2);
     End
     Else Progress (1,3);
  TimeSlice;

  { Backup Data Directory }
  If Config.Data Then
     Begin
       Progress(2,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Data.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.DataPath + Config.Masks[2];
       WindowExec(Archiver,Params,Path);
       Progress(2,2);
     End
     Else Progress (2,3);
  TimeSlice;

  { Backup File Directory }
  If Config.Files Then
     Begin
       Progress(3,1);
       Params   := Dest + ' ' + Config.BackupPath + 'File.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.FilePath + Config.Masks[3];
       WindowExec(Archiver,Params,Path);
       Progress(3,2);
     End
     Else Progress (3,3);
  TimeSlice;

  { Backup Language Directory }
  If Config.Lang Then
     Begin
       Progress(4,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Lang.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.LangPath + Config.Masks[4];
       WindowExec(Archiver,Params,Path);
       Progress(4,2);
     End
     Else Progress (4,3);
  TimeSlice;

  { Backup Logs Directory }
  If Config.Logs Then
     Begin
       Progress(5,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Logs.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.LogsPath + Config.Masks[5];
       WindowExec(Archiver,Params,Path);
       Progress(5,2);
     End
     Else Progress (5,3);
  TimeSlice;

  { Backup Menu Directory }
  If Config.Menu Then
     Begin
       Progress(6,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Menu.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.MenuPath + Config.Masks[6];
       WindowExec(Archiver,Params,Path);
       Progress(6,2);
      End
      Else Progress(6,3);
  TimeSlice;

  { Backup Text Directory }
  If Config.Text Then
     Begin
       Progress(7,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Text.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.TextPath + Config.Masks[7];
       WindowExec(Archiver,Params,Path);
       Progress(7,2);
     End
     Else Progress(7,3);
  TimeSlice;

  { Backup Message Directory }
  If Config.Msgs Then
     Begin
       Progress(8,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Msgs.' +
                   Archivers[Config.Archiver].Ext;
       Path := Telegard.MsgPath + Config.Masks[8];
       WindowExec(Archiver,Params,Path);
       Progress(8,2);
     End
     Else Progress(8,3);
  TimeSlice;

  { Backup Extra1 Directory }
  If (Config.Extra1 <> '') and (DirExist(Config.Extra1)) Then
     Begin
       Progress(9,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Extra1.' +
                   Archivers[Config.Archiver].Ext;
       Path := Config.Extra1 + '*.*';
       WindowExec(Archiver,Params,Path);
       Progress(9,2);
     End
     Else Progress(9,3);
  TimeSlice;

  { Backup Extra2 Directory }
  If (Config.Extra2 <> '') and (DirExist(Config.Extra2)) Then
     Begin
       Progress(10,1);
       Params   := Dest + ' ' + Config.BackupPath + 'Extra2.' +
                   Archivers[Config.Archiver].Ext;
       Path := Config.Extra2 + '*.*';
       WindowExec(Archiver,Params,Path);
       Progress(10,2);
     End
     Else Progress(10,3);
  TimeSlice;

 End;  { Backup }

{---------------------------------------------------------------------------}

Procedure CompileBackups (Config : tConfigRec; Archivers : tArchiverArray);
Var
   Archiver : String[12];
   Params   : String[120];
   Path     : String[120];
   Dest     : String[120];
   TempStr  : String;
   F        : File;

 Begin { CompileBackups }

  Archiver := Archivers[Config.Archiver].Filename;
  Dest     := Archivers[Config.Archiver].Compress;
  Path     := ' ';

  Progress(11,1);

  { Change to the Destination Directory }
  TempStr := Config.BackupPath;
  If (Length(TempStr) > 3) Then
    While TempStr[Length(TempStr)] = '\' Do Dec(TempStr[0]);
  ChDir(TempStr);

  { Erase existing backups with the same name }
  If fExist (Prefix + '.' + Archivers[Config.Archiver].Ext) then
     Begin
       Assign(F,Prefix + '.' + Archivers[Config.Archiver].Ext);
       Erase(F);
     End;
  TimeSlice;

  Params := Dest + ' ' + Config.BackupPath + Prefix + '.' +
            Archivers[Config.Archiver].Ext;
  If Config.Main Then Path := Path + 'Main.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Data Then Path := Path + 'Data.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Files Then Path := Path + 'File.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Logs Then Path := Path + 'Lang.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Logs Then Path := Path + 'Logs.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Menu Then Path := Path + 'Menu.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Text Then Path := Path + 'Text.' + Archivers[Config.Archiver].Ext + ' ';
  If Config.Msgs Then Path := Path + 'Msgs.' + Archivers[Config.Archiver].Ext + ' ';
  If fExist('Extra1.' + Archivers[Config.Archiver].Ext) or
     fExist('Extra2.' + Archivers[Config.Archiver].Ext) then
     Path := Path + 'Extra?.' + Archivers[Config.Archiver].Ext + ' ';
  WindowExec(Archiver,Params,Path);
  Progress(11,2);
  TimeSlice;

 End;  { CompileBackups }

{---------------------------------------------------------------------------}

Procedure CleanUp (Config : tConfigRec; Archivers : tArchiverArray);
Var
   F     : File;
   I     : Integer;
   Files : Array [1..10] of String[12];

 Begin { CleanUp }

  Files[1] := 'Main.' + Archivers[Config.Archiver].Ext;
  Files[2] := 'Data.' + Archivers[Config.Archiver].Ext;
  Files[3] := 'File.' + Archivers[Config.Archiver].Ext;
  Files[4] := 'Lang.' + Archivers[Config.Archiver].Ext;
  Files[5] := 'Logs.' + Archivers[Config.Archiver].Ext;
  Files[6] := 'Menu.' + Archivers[Config.Archiver].Ext;
  Files[7] := 'Text.' + Archivers[Config.Archiver].Ext;
  Files[8] := 'Msgs.' + Archivers[Config.Archiver].Ext;
  Files[9] := 'Extra1.' + Archivers[Config.Archiver].Ext;
  Files[10] := 'Extra2.' + Archivers[Config.Archiver].Ext;

  For I := 1 to 10 Do
     If fExist(Files[I]) then
        Begin
          Assign(F,Files[I]);
          Erase(F);
        End;
  TimeSlice;

 End;  { CleanUp }

{---------------------------------------------------------------------------}

Procedure AddToLog (Telegard : ConfigRec);
Var
   Log : Text;
   Date : String[8];
   Time : String[9];
   St   : String[4];
   Pm   : Boolean;

 Begin { AddToLog }

  GetDate(Year, Month, Day, DoW);
  GetTime(Hour, Minute, Second, Sec100);
  Date := ''; Time := '';

  Str(Month,St);
  If Month < 10 Then Date := Date + '0' + St Else Date := Date + St;
  Date := Date + '/';
  Str(Day,St);
  If Day < 10 Then Date := Date + '0' + St Else Date := Date + St;
  Date := Date + '/';
  Str(Year,St);
  Delete(St,1,2);
  Date := Date + St;

  Pm := (Hour > 12);
  If Pm then Str(Hour-12,St) else Str(Hour,St);
  If Hour < 10 then Time := Time + '0' + St else Time := Time + St;
  Time := Time + ':';
  Str(Minute,St);
  If Minute < 10 then Time := Time + '0' + St else Time := Time + St;
  Time := Time + ':';
  Str(Second,St);
  If Second < 10 then Time := Time + '0' + St else Time := Time + St;
  If Pm then Time := Time + 'p' else Time := Time + 'a';

  Assign(Log,Telegard.LogsPath + 'Sysop.Log');
  Append(Log);
  Writeln(Log);
  Writeln(Log,'                `08ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
  Writeln(Log,'                `08³                `0BTelegard Backup                `08³');
  Writeln(Log,'                `08³`03-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-`08³');
  Writeln(Log,'                `08³   `0FSystem backed up on ',Date,' at ',Time,'   `08³');
  Writeln(Log,'                `08ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ`07');
  Writeln(Log);
  Close(Log);

 End;  { AddToLog }

{---------------------------------------------------------------------------}

Procedure Maintenance(Config : tConfigRec);
Const
 DaysPerMonth :
 Array[1..12] of ShortInt = (031,028,031,030,031,030,031,031,030,031,030,031);
Var
  DT     : DateTime;
  Target : LongInt;
  fDate  : LongInt;
  fUnix  : LongInt;
  DirInfo: SearchRec;
  F      : File;

 Begin { Maintenance }

  { Find target purge date ... }
  GetDate(Year, Month, Day, DoW);
  DT.Year := Year;   DT.Month := Month;   DT.Day  := Day;
  PackUnixTime(DT,Target);
  Target := Target - (Config.KeepDays * 86400);

  FindFirst(Config.BackupPath + 'TGB-????.*', Archive, DirInfo);
  While DosError = 0 do
    Begin
      If IsNum(Copy(DirInfo.Name,5,4)) then
        Begin
          Assign(F,Config.BackupPath + DirInfo.Name);
          {$I-} Reset(F); {$I+}
          GetFTime(F,fDate);
          UnPackTime(fDate,DT);
          PackUnixTime(DT,fUnix);
          Close(f);
          If fUnix < Target then Erase(F);
        End;
      FindNext(DirInfo);
    End;

 End; { Maintenance }

{---------------------------------------------------------------------------}

Procedure ParseCmdline;
Var Count : Byte; St : String[8];

 Begin { ParseCmdline }

  For Count := 1 to ParamCount do
    Begin
       St := ParamStr(Count);
       If (St[1] in ['-','/']) then
       Case Upcase(St[2]) of
         'A': Begin
                St := UpcaseStr(ParamStr(Count+1));
                If St = 'ZIP' then ArcType := 1 else
                If St = 'ARJ' then ArcType := 2 else
                If St = 'LHA' then ArcType := 3 else
                If St = 'RAR' then ArcType := 4 else
                                   ArcType := 0;
                Inc(Count);
              End;
         'B': Begin
                ArcName := ParamStr(Count+1);
                Inc(Count);
              End;
         'C': Configuration;
         'M': Begin
                ReadConfig(ConfigName);
                If Config.KeepDays <> 0 then
                  Begin
                    Maintenance(Config);
                    Halt(0);
                  End else
                  Begin
                    TextColor(Cyan); Writeln;
                    Writeln('    Maintenance was not performed because no purge value has been set in');
                    Writeln('    TGBackup''s configuration. Run TGBackup -C to set a value for purging.');
                    Halt(2);
                  End;
              End;
        End; { Case }
    End;

 End; { ParseCmdline }

{---------------------------------------------------------------------------}
{                               .ùúMainúBodyúù.                             }
{---------------------------------------------------------------------------}

Begin { TGBackup }

 OrigPath := CurrentPath; { Store the current directory so we can return }
 ArcName  := '';

 DefineArchivers(Archivers);

 ProgInfo;
 OSDetect;
 If OperatingSystem <> _Dos then
   Begin
     Writeln;
     TextColor(Cyan);
     Write('Releasing timeslices under ');
     Case OperatingSystem of
        _DV : Write('DesqView');
       _Os2 : Write('OS/2');
       _Win : Write('Windows');
      End; { Case }
     Writeln(' v',OsMajor,'.',OsMinor,'.');
     TimeSlice;
     Delay(150);
     TimeSlice;
   End;

 If ParamCount > 0 then ParseCmdline;
 ReadConfig(ConfigName);
 ReadTelegard;

 { Override configured archiver via commandline }
 If ArcType <> 0 then Config.Archiver := ArcType;

 If Config.Fades then
    Begin
      TimeSlice;
      FadeOut(15);
      ClrScr;
      CursorOff;
      Move(Main,Screen,4000);
      GotoXY (43,3); TextColor(DarkGray); Write(Version);
      TimeSlice;
      FadeIn(15);
      TimeSlice;
    End else
    Begin
      ClrScr;
      CursorOff;
      Move(Main,Screen,4000);
      GotoXY (43,3); TextColor(DarkGray); Write(Version);
      TimeSlice;
    End;

 DrawHeader;
 Backup(Config,Telegard,Archivers);
 CompileBackups(Config,Archivers);
 CleanUp(Config,Archivers);
 If Config.KeepDays <> 0 then Maintenance(Config);

 AddToLog(Telegard);

 Window(1,1,80,25);
 If Config.Fades then
    Begin
      TimeSlice;
      FadeOut(15);
      ClrScr;
      ProgInfo;
      TimeSlice;
      FadeIn(15);
      TimeSlice;
    End else
    Begin
      ClrScr;
      ProgInfo;
      TimeSlice;
    End;

 {$I-} ChDir(OrigPath); {$I+}
 CursorOn;

End.  { TGBackup }