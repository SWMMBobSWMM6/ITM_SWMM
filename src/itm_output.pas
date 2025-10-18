unit itm_output;

{-------------------------------------------------------------------}
{                    Unit:    itm_output.pas                        }
{                    Project: ITM SWMM                              }
{                    Version: 1.0                                   }
{                    Date:    12/05/24                              }
{                                                                   }
{   Delphi Pascal unit that retrieves ITM simulation results from   }
{   binary output files.                                            }
{-------------------------------------------------------------------}
{
   Format of ITM output file:

   Magic Number (= 516114523) (4 byte integer)
   Version (= 20001)          (4 byte integer)
   NumNodes                   (4 byte integer)
   NumLinks                   (4 byte integer)
   NumNodeInputs              (4 byte integer)
   NumLinkInputs              (4 byte integer)
   NumNodeOutputs (= 5)       (4 byte integer)
   NumLinkOutputs (= 4)       (4 byte integer)
   Node input data            (NumNodeInputs*NumNodes bytes)
   Link input data            (NumLinkInputs*NumLinks bytes)
   Report Start (seconds)     (8 byte real)
   Report Step (seconds)      (8 byte real)
   For each report step:
       Current time           (8 byte real)
       For each node:
           Depth              (4 byte real)
           Head               (4 byte real)
           Volume             (4 byte real)
           Lateral Flow       (4 byte real)
           Overflow           (4 byte real)
       For each link:
           Flow               (4 byte real)
           Depth              (4 byte real)
           Velocity           (4 byte real)
           Froude No.         (4 byte real)
   Number of report steps     (4 byte integer)
   Status flag                (4 byte integer)
   Magic Number               (4 byte integer)
}

interface

uses
  SysUtils, Classes, Windows, Uglobals, Uproject, Math, Dialogs;

function  CheckItmRunStatus: TRunStatus;
function  OpenItmOutputFile: TRunStatus;
procedure ClearItmOutput;
procedure CloseItmOutputFile;
function  GetNodeItmOutVal(const V: Integer; const P: LongInt;
          const I: Integer):Single;
procedure GetNodeItmOutVals(const V: LongInt; const P: Integer;
          var Value: array of Single);
function  GetLinkItmOutVal(const V: Integer; const P: LongInt;
          const I: Integer):Single;
procedure GetLinkItmOutVals(const V: Integer; const P: LongInt;
          var Value: array of Single);
function GetLinkItmDepthVals(const LinkIndex: Integer;
         const Period: LongInt; var Station: array of Double;
         var Depths: array of Double): Integer;

implementation

const
  MagicNumber = 516114523; // File signature
  RECORDSIZE  = 4;         // Byte size of each record

var
  Fitm    : Integer;
  Fplt    : Integer;
  Offset1 : Integer;
  Offset2 : Integer;
  NumNodes: Integer;
  NumLinks: Integer;
  NumPipes: Integer;
  NumSteps: Integer;
  NumNodeOutputs: Integer;
  NumLinkOutputs: Integer;
  MaxItmCells: Integer;

function CheckItmRunStatus: TRunStatus;
//-----------------------------------------------------------------------------
// Checks if a successful simulation run was made.
//-----------------------------------------------------------------------------
var
  Mfirst : Integer;
  Mlast  : Integer;
  Version: Integer;
  ErrFlag: Integer;
  UnitsFlag: Integer;
  NumNodeInputs: Integer;
  NumLinkInputs: Integer;
begin
  // Open binary output file
  Result := OpenItmOutputFile;
  if Result = rsError then Exit;

  try
    // Read # time steps, error code & file signature from end of file
    NumPipes := Project.Lists[CONDUIT].Count;
    FileRead(Fplt, MaxItmCells, SizeOf(Integer));
    FileSeek(Fitm, -3*RecordSize, 2);
    FileRead(Fitm, NumSteps, SizeOf(NumSteps));
    Uglobals.Nperiods := NumSteps;
    FileRead(Fitm, ErrFlag, SizeOf(ErrFlag));
    FileRead(Fitm, Mlast, SizeOf(Mlast));

    // Read prolog portion of output file
    FileSeek(Fitm, 0, 0);
    FileRead(Fitm, Mfirst, SizeOf(Mfirst));
    FileRead(Fitm, Version, SizeOf(Version));
    FileRead(Fitm, UnitsFlag, SizeOf(UnitsFlag));
    FileRead(Fitm, NumNodes, SizeOf(NumNodes));
    FileRead(Fitm, NumLinks, SizeOf(NumLinks));
    FileRead(Fitm, NumNodeInputs, SizeOf(NumNodeInputs));
    FileRead(Fitm, NumLinkInputs, SizeOf(NumLinkInputs));
    FileRead(Fitm, NumNodeOutputs, SizeOf(NumNodeOutputs));
    FileRead(Fitm, NumLinkOutputs, SizeOf(NumLinkOutputs));

    // Set byte offset where simulation results begin
    Offset1 := (9 +                      // 1st 9 integers in file
                NumNodeInputs*NumNodes + // node input values
                NumLinkInputs*NumLinks + // link input values
                4) * RECORDSIZE;         // start time & time step as doubles

    // Set number of bytes used to record results in each time period
    Offset2 := RECORDSIZE * (2 +            // Current time (double)
                NumNodes*NumNodeOutputs +   // Node results
                NumLinks*NumLinkOutputs);   // Link results

    // Check if run was completed
    if Mlast <> MagicNumber then Result := rsError

    // Ckeck if results were saved for 1 or more time periods
    else if NumSteps <= 0 then Result := rsError

    // Check if correct version was used
    else if (Mfirst <> MagicNumber)
    then Result := rsWrongVersion

    // Check if error messages were generated
    else if ErrFlag <> 0 then Result := rsError
    else Result := rsSuccess;

  except
    Result := rsError;
  end;
end;


function OpenItmOutputFile: TRunStatus;
//-----------------------------------------------------------------------------
//  Opens the ITM binary output file.
//-----------------------------------------------------------------------------
begin
  Result := rsSuccess;
  Fitm := FileOpen(TempItmOutFile, fmOpenRead);
  Fplt := FileOpen(TempItmPltFile, fmOpenRead);
  if (Fitm < 0) or (Fplt < 0) then Result := rsError;
end;


procedure ClearItmOutput;
//-----------------------------------------------------------------------------
//  Closes ITM binary output results file
//-----------------------------------------------------------------------------
begin
  if RunFlag then
  begin
    FileClose(Fitm);
    FileClose(Fplt);
  end;
end;


procedure CloseItmOutputFile;
//-----------------------------------------------------------------------------
//  Closes ITM binary output file.
//-----------------------------------------------------------------------------
begin
  FileClose(Fitm);
  FileClose(Fplt);
end;


function GetNodeItmOutVal(const V: Integer; const P: LongInt;
  const I: Integer):Single;
//-----------------------------------------------------------------------------
//  Returns the computed value for variable V at time period P
//  for node I.
//-----------------------------------------------------------------------------
var
  Pos: Int64;
  K: Integer;
begin
  Result := MISSING;
  case V + NODEOUTVAR1 of
  NODEDEPTH: K := 0;
  HEAD:      K := 1;
  VOLUME:    K := 2;
  LATFLOW:   K := 3;
  OVERFLOW:  K := 4;
  else exit;
  end;

  Pos := Offset1 + P*Offset2 + SizeOf(Double) +
       RecordSize*(I*NumNodeOutputs + K);
  FileSeek(Fitm, Pos, 0);
  FileRead(Fitm, Result, SizeOf(Single));
end;


function GetLinkItmOutVal(const V: Integer; const P: LongInt;
  const I: Integer):Single;
//-----------------------------------------------------------------------------
//  Returns the computed value for variable V at time period P
//  for link I.
//-----------------------------------------------------------------------------
var
  Pos: Int64;
  K: Integer;
begin
  Result := MISSING;

  case V + LINKOUTVAR1 of
  FLOW:      K := 0;
  LINKDEPTH: K := 1;
  VELOCITY:  K := 2;
  else exit;
  end;

  Pos := Offset1 + P*Offset2 + SizeOf(Double) +
       RecordSize*(NumNodes*NumNodeOutputs + I*NumLinkOutputs + K);
  FileSeek(Fitm, Pos, 0);
  FileRead(Fitm, Result, SizeOf(Single));
end;


procedure GetNodeItmOutVals(const V: LongInt; const P: Integer;
  var Value: array of Single);
//-----------------------------------------------------------------------------
//  Gets computed results for all nodes from the ITM output file where:
//  V = node variable code
//  P = time period index
//  Value = array that stores the retrieved values
//-----------------------------------------------------------------------------
var
  Pos1, Pos2: Int64;
  I, K: Integer;
begin
  if (NumNodes > 0) and (V <> NONE) and (P < Nperiods) then
  begin
    case V of
    NODEDEPTH: K := 0;
    HEAD:      K := 1;
    VOLUME:    K := 2;
    LATFLOW:   K := 3;
    OVERFLOW:  K := 4;
    else
      begin
        for I := 0 to NumNodes-1 do Value[I] := MISSING;
        exit;
      end;
    end;

    Pos1 := Offset1 + P*Offset2 + SizeOf(Double) + RecordSize*(K);
    FileSeek(Fitm, Pos1, 0);
    FileRead(Fitm, Value[0], SizeOf(Single));

    Pos2 := RecordSize*(NumNodeOutputs-1);
    for I := 1 to NumNodes-1 do
    begin
      FileSeek(Fitm, Pos2, 1);
      FileRead(Fitm, Value[I], SizeOf(Single));
    end;
  end;
end;


procedure GetLinkItmOutVals(const V: Integer; const P: LongInt;
  var Value: array of Single);
//-----------------------------------------------------------------------------
//  Gets computed results for all links from the ITM output file where:
//  V = link variable code
//  P = time period index
//  Value   = array that stores the retrieved values
//-----------------------------------------------------------------------------
var
  Pos1, Pos2: Int64;
  I, K : Integer;
begin
  if (NumLinks > 0) and (V <> NONE) and (P < Nperiods) then
  begin
    case V of
    FLOW:      K := 0;
    LINKDEPTH: K := 1;
    VELOCITY:  K := 2;
    else
      begin
        for I := 0 to NumLinks-1 do Value[I] := MISSING;
        exit;
      end;
    end;

    Pos1 := Offset1 + P*Offset2 + SizeOf(Double) +
      RecordSize*(NumNodes*NumNodeOutputs + K);
    FileSeek(Fitm, Pos1, 0);
    FileRead(Fitm, Value[0], SizeOf(Single));

    Pos2 := RecordSize*(NumLinkOutputs - 1);
    for I := 1 to NumLinks-1 do
    begin
      FileSeek(Fitm, Pos2, 1);
      FileRead(Fitm, Value[I], SizeOf(Single));
    end;
  end;
end;


function GetLinkItmDepthVals(const LinkIndex: Integer;
  const Period: LongInt; var Station: array of Double;
  var Depths: array of Double): Integer;
//-----------------------------------------------------------------------------
//  Returns distances & water depths ITM computed for a specific pipe.
//-----------------------------------------------------------------------------
var
  P: Int64;
  TS: Double;
  Count: Integer;
  ID: Integer;
  RecSize: Integer;
begin
  if (Fplt >= 0) and (LinkIndex >= 0) then
  begin
    // The size of an individual record for a given link.
    // (time, link index, number of cells)
    // (stations for MaxItmCells)
    // (depths for MaxItmCells)
    RecSize := (SizeOf(Double) + SizeOf(Integer) * 2 +
                SizeOf(Double) * MaxITMCells * 2);

    // File offset to start of data for specified Period
    // (first value in file is MaxItmCells)
    P := SizeOf(Integer) + (Period - 1) * NumPipes * RecSize;
    if (P < 0) then
      P := SizeOf(Integer);

    // File position where data for specified link begins
    // (LinkIndex is 0-based)
    FileSeek(Fplt, P + LinkIndex * RecSize, 0);

    // Grab the data from the link
    FileRead(Fplt, TS, SizeOf(Double));            //Time stamp
    FileRead(Fplt, ID, SizeOf(Integer));           //ITM link index
    FileRead(Fplt, Count, SizeOf(Integer));        //Number of cells
    FileRead(Fplt, Station[0], Count * SizeOf(Double));
    FileRead(Fplt, Depths[0], Count * SizeOf(Double));

    if (ID <> LinkIndex + 1) then
    begin
      Result := -1; // error
    end
    else
      Result := Count;
  end
  else
    Result := -1;
end;


end.
