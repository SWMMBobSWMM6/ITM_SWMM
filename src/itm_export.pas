unit itm_export;

{-------------------------------------------------------------------}
{                    Unit:    itm_export.pas                        }
{                    Project: ITM SWMM                              }
{                    Version: 1.0                                   }
{                    Date:    02/28/25                              }
{                                                                   }
{   Delphi Pascal unit that exports current project data to an      }
{   ITM formatted input file.                                       }
{-------------------------------------------------------------------}

interface

uses SysUtils, Windows, Messages, Classes, Math, Dialogs, StrUtils,
  DateUtils, Types;

function  ExportItmProject(ItmFile, RunoffFile: String): Boolean;

implementation

uses
  Uglobals, Uutils, Uproject, Uupdate;

const
  Tab = '  ';
  STORAGE_CURVE = 1;
  PUMP_CURVE    = 2;
  RATING_CURVE  = 3;
  CONTROL_CURVE = 4;
  CurveType: array[1..4] of Integer =
    (STORAGECURVE, PUMPCURVE, RATINGCURVE, CONTROLCURVE);

var
  NodeStartIndex: array[JUNCTION .. STORAGE] of Integer;
  CurveStartIndex: array[1..4] of Integer;
  NumCurves: Integer;        // Number of curves used by ITM objects
  FlowUnitsIndex: Integer;   // Index in [CFS, GPM, MGD, CMS, LPS, MLD]
  FlowCF: Extended;          // Units conversion factor for flow rate
  LengthCF: Extended;        // Units conversion factor for length
  InflowList: TStringlist;   // List of inflows used by ITM junctions


procedure SetConversionFactors;
//-----------------------------------------------------------------------------
// ITM assumes length in meters and flow in CMS
//-----------------------------------------------------------------------------
var
  I: Integer;
begin
  LengthCF := 1.0;
  FlowCF := 1.0;

  if Uglobals.UnitSystem = Uglobals.usSI then
  begin
    I := AnsiIndexStr(Uglobals.FlowUnits, ['CMS', 'LPS', 'MLD']);
    FlowUnitsIndex := 3 + I;
    if I = 1 then FlowCF := 0.001;
    if I = 2 then FlowCF := 1000 / (3600 * 24);
  end

  else begin
    LengthCF := 0.3048;
    I := AnsiIndexStr(Uglobals.FlowUnits, ['CFS', 'GPM', 'MGD']);
    FlowUnitsIndex := I;
    case I of
    0: FlowCF := 0.028317;
    1: FlowCF := 0.00378541 / 60.0;
    2: FlowCF := 3785.41 / (3600.0 * 24.0);
    end;
  end;

end;


function ConvertUnits(Value: String; Ucf: Double): String;
//-----------------------------------------------------------------------------
// Apply unit conversion factor to a numeric string value
//-----------------------------------------------------------------------------
var
  X: Extended;
begin
  if Length(Value) = 0 then Value := '0';
  Result := Value;
  if Ucf = 1.0 then exit;
  Uutils.GetExtended(Value, X);
  X := X * Ucf;
  Result := FloatToStrF(X, ffFixed, 12, 5);
end;


function ConvertSetting(Value: String): String;
//-----------------------------------------------------------------------------
// Converts a fractional control setting to a percent
//-----------------------------------------------------------------------------
var
  X: Single;
begin
  Uutils.GetSingle(Value, X);
  Result := FloatToStrF(X*100, ffFixed, 7, 3);
end;


function GetNodeIndex(NodeName: String): Integer;
//-----------------------------------------------------------------------------
// Get the index of a node given its ID name
//-----------------------------------------------------------------------------
var
  J, K: Integer;
begin
  if not Project.FindNode(NodeName, J, K) then Result := -1
  else
    Result := NodeStartIndex[J] + K;
end;


function GetCurveIndex(CurveType: Integer; CurveName: String): Integer;
var
  I: Integer;
begin
  I := 0;
  Result := Project.Lists[CurveType].IndexOf(CurveName);
  case CurveType of
  STORAGECURVE: I := STORAGE_CURVE;
  PUMPCURVE:    I := PUMP_CURVE;
  RATINGCURVE:  I := RATING_CURVE;
  CONTROLCURVE: I := CONTROL_CURVE;
  end;
  Result := Result + CurveStartIndex[I];
end;


procedure ExportCounts(S: TStringlist);
//-----------------------------------------------------------------------------
// Write number of each type of network component to stringlist S
//-----------------------------------------------------------------------------
var
  NumNodes: Integer;
  I: Integer;
begin
  // Number of nodes
  NodeStartIndex[JUNCTION] := 0;
  NumNodes := Project.Lists[JUNCTION].Count;
  for I := JUNCTION+1 to STORAGE do
  begin
    NodeStartIndex[I] := NodeStartIndex[I-1] + Project.Lists[I-1].Count;
    NumNodes := NumNodes + Project.Lists[I].Count;
  end;
  S.Add(IntToStr(NumNodes));

  // Number of pipes, pumps, orifices, weirs & outlets
  for I := CONDUIT to OUTLET do
    S.Add(IntToStr(Project.Lists[I].Count));

  // Number of curves
  CurveStartIndex[1] := 0;
  NumCurves := Project.Lists[STORAGECURVE].Count;
  CurveStartIndex[2] := NumCurves;
  NumCurves := NumCurves + Project.Lists[PUMPCURVE].Count;
  CurveStartIndex[3] := NumCurves;
  NumCurves := NumCurves + Project.Lists[RATINGCURVE].Count;
  CurveStartIndex[4] := NumCurves;
  NumCurves := NumCurves + Project.Lists[CONTROLCURVE].Count;
  S.Add(IntToStr(NumCurves));

  // Number of time series
  S.Add(IntToStr(Project.Lists[TIMESERIES].Count));

  // Number of runoffs from subcatchments
  S.Add(IntToStr(Project.Lists[SUBCATCH].Count));

end;


procedure ExportJunctions(S: TStringlist);
//-----------------------------------------------------------------------------
// Write data for each Junction node to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  Line: String;
  N: TNode;
  X: Extended;
begin
  with Project.Lists[JUNCTION] do
  begin
    // Write number of junctions
    S.Add(IntToStr(Count));

    // Write properties for each junction (converted to SI units)
    for I := 0 to Count-1 do
    begin
      N := TNode(Objects[I]);
      Line := Strings[I];
      Line := Line + Tab + ConvertUnits(N.Data[NODE_INVERT_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(N.Data[JUNCTION_MAX_DEPTH_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(N.Data[JUNCTION_INIT_DEPTH_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(N.Data[JUNCTION_ITM_AREA_INDEX],
          LengthCF*LengthCF);
      Uutils.GetExtended(N.Data[JUNCTION_ITM_AREA_INDEX], X);
      if X > 0 then
        Line := Line + Tab + '0'
      else
        Line := Line + Tab + '1';
      S.Add(Line);
    end;
  end;
end;

function GetBoundaryDepth(aNode: TNode): String;
var
  Invert, Stage, Depth: Single;
begin
  Uutils.GetSingle(aNode.Data[NODE_INVERT_INDEX], Invert);
  Uutils.GetSingle(aNode.Data[OUTFALL_FIXED_STAGE_INDEX], Stage);
  Depth := (Stage - Invert) * LengthCF;
  Result := FloatToStrF(Depth, ffFixed, 12, 5);
end;


procedure ExportBoundaries(S: TStringlist);
//-----------------------------------------------------------------------------
// Write boundary (outfall) node data to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  Line: String;
  N: TNode;
begin
  with Project.Lists[OUTFALL] do
  begin
    // Write number of outfalls
    S.Add(IntToStr(Count));

    // Write properties for each outfall (converted to SI units)
    for I := 0 to Count-1 do
    begin
      N := TNode(Objects[I]);
      Line := Strings[I];
      Line := Line + Tab + ConvertUnits(N.Data[NODE_INVERT_INDEX], LengthCF);

      // Only fixed depth outfall (not flow) supported (ITM code is 11)
      Line := Line + Tab + '11';
      Line := Line + Tab + GetBoundaryDepth(N);
      Line := Line + Tab + '0';  // Outfall always vented (ITM code is 0)
      S.Add(Line);
    end;
  end;
end;


procedure ExportStorage(S: TStringlist);
//-----------------------------------------------------------------------------
// Write storage node data to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  J: Integer;
  N: TNode;
  Line: String;
begin
  with Project.Lists[STORAGE] do
  begin
    // Write number of storage nodes
    S.Add(IntToStr(Count));

    // Write properties of each storage node (converted to SI units)
    for I := 0 to Count-1 do
    begin
      N := TNode(Objects[I]);
      Line := Strings[I];
      Line := Line + Tab + ConvertUnits(N.Data[NODE_INVERT_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(N.Data[STORAGE_MAX_DEPTH_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(N.Data[STORAGE_INIT_DEPTH_INDEX], LengthCF);
      J := GetCurveIndex(STORAGECURVE, N.Data[STORAGE_ATABLE_INDEX]);
      Line := Line + Tab + IntToStr(J+1);

      // Fixed storage outflow not supported
      Line := Line + Tab + '0';
      S.Add(Line);
    end;
  end;
end;


procedure ExportConduits(S: TStringlist);
//-----------------------------------------------------------------------------
// Write pipe data to stringlist S
//-----------------------------------------------------------------------------
var
  I     : Integer;
  J     : Integer;
  K     : Integer;
  Line  : String;
  Dtype : String;
  L     : TLink;
begin
  with Project.Lists[CONDUIT] do
  begin
    // Write number of pipes
    S.Add(IntToStr(Count));

    // Write properties of each pipe (converted to SI units)
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      Line := Strings[I];
      K := GetNodeIndex(L.Node1.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetNodeIndex(L.Node2.ID);
      Line := Line + Tab + IntToStr(K+1);
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_GEOM1_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_LENGTH_INDEX], LengthCF);
      Line := Line + Tab + L.Data[CONDUIT_ROUGHNESS_INDEX];
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_INLET_HT_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_OUTLET_HT_INDEX], LengthCF);
      Line := Line + Tab + L.Data[CONDUIT_ENTRY_LOSS_INDEX];
      Line := Line + Tab + L.Data[CONDUIT_EXIT_LOSS_INDEX];
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_INIT_FLOW_INDEX], FlowCF);
      Line := Line + Tab + ConvertUnits(L.Data[CONDUIT_ITM_INIT_DEPTH_INDEX], LengthCF);
      Dtype := L.Data[CONDUIT_ITM_INIT_TYPE_INDEX];
      if      SameText(Dtype, 'CONSTANT') then J := 1
      else if SameText(Dtype, 'CRITICAL') then J := 2
      else if SameText(Dtype, 'NORMAL')   then J := 3
      else J := -1;
      Line := Line + Tab + IntToStr(J);
      S.Add(Line);
    end;
  end;
end;


function GetControlLine(L: TLink; LinkType: Integer; CtrlIndex: Integer): String;
//-----------------------------------------------------------------------------
// Place the control properties of a link into a string
//   L = link object
//   LinkType = type of link,
//   CtrlIndex = index of control type in link's Data array.
//   CtrlIndex + 1 contains time series name;
//   CtrlIndex + 2 contains control node name;
//   CntrlIndex + 3 contains control curve name
//-----------------------------------------------------------------------------
var
  J: Integer;
begin
  // Time series control (Result = '1 TimeSeriesIndex 0 0')
  if SameText(L.Data[CtrlIndex], 'TIME') then
  begin
    Result := '1 ';
    J := Project.Lists[TIMESERIES].IndexOf(L.Data[CtrlIndex + 1]);
    Result := Result + ' ' + IntToStr(J+1) + ' 0 0';
  end

  // Node depth control (Result = '2 0 NodeIndex CurveIndex')
  else if SameText(L.Data[CtrlIndex], 'DEPTH') then
  begin
    Result := '2  0 ';
    J := GetNodeIndex(L.Data[CtrlIndex + 2]);
    Result := Result + ' ' + IntToStr(J+1);
    J := GetCurveIndex(CONTROLCURVE, L.Data[CtrlIndex + 3]);
    Result := Result + ' ' + IntToStr(J+1);
  end

  // Result if link has no control
  else Result := '0 0 0 0';
end;


procedure ExportPumps(S: TStringlist);
//-----------------------------------------------------------------------------
// Write pump data to stringlist S
//-----------------------------------------------------------------------------
var
  I   : Integer;
  K   : Integer;
  N   : Integer;
  L   : TLink;
  Line: String;
begin
  // Write number of pumps
  N := Project.Lists[PUMP].Count;
  S.Add(IntToStr(N));

  // Write properties for each pump
  if N > 0 then with Project.Lists[PUMP] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      Line := Strings[I];
      K := GetNodeIndex(L.Node1.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetNodeIndex(L.Node2.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetCurveIndex(PUMPCURVE, L.Data[PUMP_CURVE_INDEX]);
      Line := Line + Tab + IntToStr(K+1);
      Line := Line + Tab + ConvertSetting(L.Data[PUMP_ITM_SETTING_INDEX]);
      S.Add(Line);

      // Write pump control parameters
      S.Add(GetControlLine(L, PUMP, PUMP_ITM_METHOD_INDEX));
    end;
  end;
end;


procedure ExportOrifices(S: TStringlist);
//-----------------------------------------------------------------------------
// Write orifice data to stringlist S
//-----------------------------------------------------------------------------
var
  I   : Integer;
  K   : Integer;
  N   : Integer;
  L   : TLink;
  Line: String;
begin
  // Write number of orifices
  N := Project.Lists[ORIFICE].Count;
  S.Add(IntToStr(N));

  // Write properties for each orifice (converted to SI units)
  if N > 0 then with Project.Lists[ORIFICE] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      Line := Strings[I];
      K := GetNodeIndex(L.Node1.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetNodeIndex(L.Node2.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := 0;
      if SameText(L.Data[ORIFICE_TYPE_INDEX], 'BOTTOM') then K := 1;
      Line := Line + Tab + IntToStr(K);
      K := 0;
      if SameText(L.Data[ORIFICE_SHAPE_INDEX], 'RECTANGULAR') then K := 1;
      Line := Line + Tab + IntToStr(K);
      Line := Line + Tab + ConvertUnits(L.Data[ORIFICE_HEIGHT_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[ORIFICE_WIDTH_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[ORIFICE_BOTTOM_HT_INDEX], LengthCF);
      Line := Line + Tab + L.Data[ORIFICE_COEFF_INDEX];
      K := 0;
      if SameText(L.Data[ORIFICE_FLAPGATE_INDEX], 'YES') then K := 1;
      Line := Line + Tab + IntToStr(K);
      Line := Line + Tab + ConvertSetting(L.Data[ORIFICE_ITM_SETTING_INDEX]);
      Line := Line + Tab + Format('%.2f',
              [StrToFloat(L.Data[ORIFICE_ORATE_INDEX]) * 60]);
      S.Add(Line);

      // Write orifice control parameters
      S.Add(GetControlLine(L, ORIFICE, ORIFICE_ITM_METHOD_INDEX));
    end;
  end;
end;


procedure ExportWeirs(S: TStringlist);
//-----------------------------------------------------------------------------
// Write weir data to stringlist S
//-----------------------------------------------------------------------------
var
  I   : Integer;
  K   : Integer;
  N   : Integer;
  L   : TLink;
  Line: String;
  CF  : Extended;
begin
  // Write number of weirs
  N := Project.Lists[WEIR].Count;
  S.Add(IntToStr(N));

  // Write properties of each weir (converted to SI units)
  if N > 0 then with Project.Lists[WEIR] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      Line := Strings[I];
      K := GetNodeIndex(L.Node1.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetNodeIndex(L.Node2.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := Uutils.FindKeyWord(L.Data[WEIR_TYPE_INDEX], WeirTypes, 3);
      if K < 0 then K := 0;
      Line := Line + Tab + IntToStr(K);
      Line := Line + Tab + ConvertUnits(L.Data[WEIR_HEIGHT_INDEX], LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[WEIR_WIDTH_INDEX], LengthCF);

      // Trapezoidal weir slope not supported
//      Line := Line + Tab + L.Data[WEIR_SLOPE_INDEX];

      Line := Line + Tab + ConvertUnits(L.Data[WEIR_CREST_INDEX], LengthCF);

      // Convert weir coeff. to meter^0.5
      CF := sqrt(LengthCF);
      Line := Line + Tab + ConvertUnits(L.Data[WEIR_COEFF_INDEX], CF);

      // Flap gate not supported
//      K := 0;
//      if SameText(L.Data[WEIR_FLAPGATE_INDEX], 'YES') then K := 1;
//      Line := Line + Tab + IntToStr(K);

      Line := Line + Tab + L.Data[WEIR_CONTRACT_INDEX];

      // End coeff. not supported
//      Line := Line + Tab + L.Data[WEIR_END_COEFF_INDEX];

      K := 0;
      if SameText(L.Data[WEIR_SURCHARGE_INDEX], 'YES') then K := 1;
      Line := Line + Tab + IntToStr(K);
      Line := Line + Tab + ConvertSetting(L.Data[WEIR_ITM_SETTING_INDEX]);

      // SWMM doesn't have a weir adjustment rate property
      Line := Line + Tab + '0';
      S.Add(Line);

      // Write weir control parameters
      S.Add(GetControlLine(L, WEIR, WEIR_ITM_METHOD_INDEX));
    end;
  end;
end;


procedure ExportOutlets(S: TStringlist);
//-----------------------------------------------------------------------------
// Write outlet data to stringlist S
//-----------------------------------------------------------------------------
var
  I   : Integer;
  K   : Integer;
  N   : Integer;
  L   : TLink;
  Line: String;
begin
  // Write number of outlets
  N := Project.Lists[OUTLET].Count;
  S.Add(IntToStr(N));

  // Write properties for each outlet (converted to SI units)
  if N > 0 then with Project.Lists[OUTLET] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      Line := Strings[I];
      K := GetNodeIndex(L.Node1.ID);
      Line := Line + Tab + IntToStr(K+1);
      K := GetNodeIndex(L.Node2.ID);
      Line := Line + Tab + IntToStr(K+1);
      Line := Line + Tab + ConvertUnits(L.Data[OUTLET_CREST_INDEX], LengthCF);
      K := 0;
      if SameText(L.Data[OUTLET_FLAPGATE_INDEX], 'YES') then K := 1;
      Line := Line + Tab + IntToStr(K);
      K := GetCurveIndex(RATINGCURVE, L.Data[OUTLET_QTABLE_INDEX]);
      Line := Line + Tab + IntToStr(K+1);
      S.Add(Line);
    end;
  end;
end;


procedure ExportInflows(S: TStringlist);
//-----------------------------------------------------------------------------
// Write external inflow data to stringlist S
// (Inflows have already been added to InflowList in ValidateInflows)
//-----------------------------------------------------------------------------
var
  I: Integer;
begin
  with Project.Lists[JUNCTION] do
  begin
    S.Add(IntToStr(Count));
    for I := 0 to Count-1 do
      S.Add(InflowList[I]);
  end;
end;


procedure ExportStorageCurve(S: TStringlist; C: TCurve; Npts: Integer);
//-----------------------------------------------------------------------------
// Writes storage curve converted from areas to volumes to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  VolumeCF: Single;
  X, Y: Single;
  D, A, V: array of Single;
begin
  // Create depth, area & volume arrays
  SetLength(D, Npts);
  SetLength(A, Npts);
  SetLength(V, Npts);
  for I := 0 to Npts-1 do
  begin
    Uutils.GetSingle(C.Xdata[I], D[I]);
    Uutils.GetSingle(C.Ydata[I], A[I]);
  end;

  // Compute volume from depth
  if D[0] = 0.0 then
    V[0] := 0.0
  else
    V[0] := D[0] * A[0];
  for I := 1 to Npts-1 do
  begin
    V[I] := V[I-1] + (D[I] - D[I-1]) * A[I];
  end;

  // Write depth (in meters) & volume (in cubic meters) for each point on curve
  VolumeCF := LengthCF * LengthCF * LengthCF;
  for I := 0 to Npts-1 do
  begin
    X := D[I] * LengthCF;
    Y := V[I] * VolumeCF;
    S.Add(FloatToStrF(X, ffFixed, 12, 5) + Tab + FloatToStrF(Y, ffFixed, 12, 5));
  end;
end;


procedure ExportPumpCurve(S: TStringlist; C: TCurve; Npts: Integer);
//-----------------------------------------------------------------------------
// Writes pump curve to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  Head, Flow: String;
begin
  // For Type 3 & 5 pump curve loop thru Head, Flow points in reverse order
  if (C.CurveCode = 3) or (C.CurveCode = 5) then
  begin
    for I := Npts-1 downto 0 do
    begin
      Head := ConvertUnits(C.Xdata[I], LengthCF);
      Flow := ConvertUnits(C.Ydata[I], FlowCF);
      S.Add(Flow + Tab + Head);
    end;
  end

  // Other types of pump curves are not used by ITM
  else for I := 0 to Npts-1 do
    S.Add(C.Xdata[I] + Tab + C.Ydata[I]);
end;


procedure ExportCurveData(S: TStringlist; C: TCurve; I, K: Integer);
//-----------------------------------------------------------------------------
// Write K data points for curve C of type I to the stringlist S
//-----------------------------------------------------------------------------
var
  J: Integer;
begin
  // Export storage curve converted from areas to volumes
  if I = STORAGE_CURVE then
    ExportStorageCurve(S, C, K)

  // Export pump curve converted to SI units
  else if I = PUMP_CURVE then
    ExportPumpCurve(S, C, K)

  // For control curves convert depth values to meters and
  // control setting to percent
  else if I = CONTROL_CURVE then
  begin
    for J := 0 to K-1 do
      S.Add(ConvertUnits(C.Xdata[J], LengthCF) + Tab +
        ConvertSetting(C.Ydata[J]));
  end

  // For rating curves convert depth to meters & flow to CMS
  else begin
    for J := 0 to K-1 do
      S.Add(ConvertUnits(C.Xdata[J], LengthCF) + Tab +
        ConvertUnits(C.Ydata[J], FlowCF));
  end;
end;


procedure ExportCurves(S: TStringlist);
//-----------------------------------------------------------------------------
// Write data for each ITM curve type to the stringlist S
//-----------------------------------------------------------------------------
var
  I, K, L, M, N: Integer;
  C: TCurve;
begin
  // Write number of curves
  S.Add(IntToStr(NumCurves));
  if NumCurves = 0 then exit;

  // Loop through each curve
  for I := STORAGE_CURVE to CONTROL_CURVE do
  begin
    M := CurveType[I];
    with Project.Lists[M] do
    begin
      N := Count;
      if N = 0 then continue;
      for L := 0 to N-1 do
      begin
        // Write number of data points in curve
        C := TCurve(Objects[L]);
        K := MinIntValue([C.Xdata.Count, C.Ydata.Count]);
        S.Add(IntToStr(K));
        ExportCurveData(S, C, I, K);
      end;

    end;
  end;
end;


function GetDateTime(S: String): Double;
//-----------------------------------------------------------------------------
// Convert a date/time string to a decimal days value
//-----------------------------------------------------------------------------
var
  D: TDateTime;
begin
  if TryStrToDateTime(S, D, MyFormatSettings) then
    Result := D
  else
    Result := 0;
end;


function GetElapsedSeconds(aDate: String; aTime: String; UseDates: Boolean;
  FirstDate: TDateTime; var LastDate: TDateTime): Double;
//-----------------------------------------------------------------------------
// Convert a time series date/time string to seconds after starting date/time
//-----------------------------------------------------------------------------
var
  T: TDateTime;   // a time in decimal days
begin
  // Convert aTime to decimal days
  T := Uutils.StrHoursToTime(aTime);
  if T < 0 then
  begin
    Result := MISSING;
    exit;
  end;

  // If dates are being used
  if UseDates then
  begin
    // Update the time series' current date
    if Length(aDate) > 0 then
    begin
      if not TryStrToDate(aDate, LastDate, MyFormatSettings) then
      begin
        Result := MISSING;
        exit;
      end;
    end;
    // Find days since FirstDate
    T := LastDate + T - FirstDate;
  end;

  // Convert elapsed days to seconds
  Result := T * 86400;
end;


procedure ExportTimeseries(S: TStringlist);
//-----------------------------------------------------------------------------
// Write data for each time series to stringlist S
//-----------------------------------------------------------------------------
var
  I: Integer;
  J: Integer;
  N: Integer;
  Tseries:  TTimeseries;
  ElapsedSeconds: Double;
  LastElapsedSeconds: Double;
  FirstDate: TDateTime;
  LastDate: TDateTime;
  UseDates: Boolean;
begin
  // Find project's starting Date/Time
  with Project.Options do
    FirstDate := GetDateTime(Data[START_DATE_INDEX] + ' ' + Data[START_TIME_INDEX]);

  with Project.Lists[TIMESERIES] do
  begin
    // Add number of time series to stringlist S
    S.Add(IntToStr(Count));

    // Loop through each time series
    for I := 0 to Count-1 do
    begin

      // Add number of entries in series to stringlist S
      Tseries := TTimeseries(Objects[I]);
      N := MinIntValue([Tseries.Times.Count, Tseries.Values.Count]);
      S.Add(IntToStr(N));

      // See if time series uses dates or not
      UseDates := Length(Tseries.Dates[0]) > 0;
      LastDate := 0;
      LastElapsedSeconds := MISSING;

      // Loop through each series entry
      for J := 0 to N-1 do
      begin

       // Determine entry's elapsed seconds from project starting date/time
       ElapsedSeconds := GetElapsedSeconds(Tseries.Dates[J], Tseries.Times[J],
         UseDates, FirstDate, LastDate);

       // If elapsed seconds invalid then just use previous value
       if (ElapsedSeconds <= LastElapsedSeconds) then
         ElapsedSeconds := LastElapsedSeconds
       else
         LastElapsedSeconds := ElapsedSeconds;

       // Add elapsed time and series value to stringlist S
       S.Add(Format('%.4f  %s', [ElapsedSeconds, Tseries.Values[J]]));
      end;
    end;
  end;
end;


procedure ExportRunoff(S: TStringlist; RunoffFile: String);
//-----------------------------------------------------------------------------
// Write runoff node indexes to stringlist S
//-----------------------------------------------------------------------------
var
  N, I, K, M: Integer;
  aSubcatch: TSubcatch;
begin
  N := Project.Lists[SUBCATCH].Count;
  S.Add(IntToStr(N));
  if N = 0 then exit;

  for I := 0 to N-1 do
  begin
    aSubcatch := TSubcatch(Project.Lists[SUBCATCH].Objects[I]);
    K := GetNodeIndex(aSubcatch.OutNode.ID);
    M := -1;
    if aSubcatch.Groundwater.Count >= 2 then
      M := GetNodeIndex(aSubcatch.Groundwater[1]);
    S.Add(IntToStr(K+1) + Tab + IntToStr(M+1));
  end;
  if Length(Trim(RunoffFile)) = 0 then RunoffFile := '*';
  S.Add(RunoffFile);

end;


procedure ExportOptions(S: TStringlist);
//-----------------------------------------------------------------------------
// Write ITM options to stringlist S
//-----------------------------------------------------------------------------
var
  StartDateTime: TDateTime;
  EndDateTime: TDateTime;
  ReportStart: TDateTime;
  Duration: Int64;
  ReportStep: Integer;
  RefDepthFrac: Double;
  WaveCelerity: String;
  InitWaterElev: String;
  HotstartFile: String;
begin
  with Project.Options do
  begin
    StartDateTime := GetDateTime(Data[START_DATE_INDEX] + ' ' + Data[START_TIME_INDEX]);
    ReportStart := (GetDateTime(Data[REPORT_START_DATE_INDEX] + ' ' +
                   Data[REPORT_START_TIME_INDEX]) - StartDateTime) * 86400.;
    EndDateTime := GetDateTime(Data[END_DATE_INDEX] + Data[END_TIME_INDEX]);
    Duration := Round((EndDateTime - StartDateTime) * 86400);
    ReportStep := SecondOfTheDay(StrToTime(Data[REPORT_STEP_INDEX]));
  end;

  with Project do
  begin
    RefDepthFrac := StrToFloat(ItmOptions[ITM_REF_DEPTH]) / 100.;
    if Length(ItmOptions[ITM_INIT_ELEV]) = 0 then
      InitWaterElev := '-99999.5'
    else
      InitWaterElev := ConvertUnits(ItmOptions[ITM_INIT_ELEV], LengthCF);
    S.Add(ItmOptions[ITM_MAX_CELLS]);
    WaveCelerity := ConvertUnits(ItmOptions[ITM_WAVE_CELERITY], LengthCF);
    S.Add(Format('%.0f', [StrToFloat(WaveCelerity)]));
    S.Add(Format('%0.3f', [RefDepthFrac]));
    S.Add(Format('%d', [Duration]));
    S.Add(ItmOptions[ITM_MAX_STEP]);
    S.Add(Format('%d', [ReportStep]));
    S.Add(Format('%.6f', [ReportStart]));
    S.Add(ItmOptions[ITM_MAX_PLOT_CELLS]);
    S.Add(InitWaterElev);
    S.Add(IntToStr(FlowUnitsIndex+1));
  end;

  // Needs to be updated to support using hotstart files
  HotstartFile := '';
  if Length(Trim(HotstartFile)) = 0 then HotstartFile := '*';
  S.Add(HotstartFile);
  HotstartFile := '';
  if Length(Trim(HotstartFile)) = 0 then HotstartFile := '*';
  S.Add(HotstartFile);
end;


procedure SaveItmProject(ItmFile, RunoffFile: String);
//-----------------------------------------------------------------------------
// Save ITM project data to a file.
//-----------------------------------------------------------------------------
var
  S: TStringlist;
  Title: String;
  ElevOffsets: Boolean;
begin
  // Units conversion factors
  SetConversionFactors;

  // Project title
  Title := ' ';
  if Project.Lists[NOTES].Count > 0  then
    Title := Project.Lists[NOTES].Strings[0];

  // Write data to stringlist S
  S := TStringlist.Create;
  try
    S.Add(Title);
    ExportCounts(S);
    ExportJunctions(S);
    ExportBoundaries(S);
    ExportStorage(S);

    // Convert elevation offsets to depth offsets
    ElevOffsets := SameText(Project.Options.Data[LINK_OFFSETS_INDEX], 'ELEVATION');
    if ElevOffsets then Uupdate.ComputeDepthOffsets;

    ExportConduits(S);
    ExportPumps(S);
    ExportOrifices(S);
    ExportWeirs(S);
    ExportOutlets(S);

    // Restore elevation offsets
    if ElevOffsets then Uupdate.ComputeElevationOffsets;

    ExportInflows(S);
    ExportCurves(S);
    ExportTimeseries(S);
    ExportOptions(S);
    ExportRunoff(S, RunoffFile);

    // Write stringlist S to file
    S.SaveToFile(ItmFile);

  finally
    S.Free;
  end;
end;


procedure ValidateNetwork(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check that a conveyance network exists.
//-----------------------------------------------------------------------------
var
  N: Integer;
  I: Integer;
begin
  // Check for empty
  N := 0;
  for I := JUNCTION to STORAGE do
    N := N + Project.Lists[I].Count;
  if (N = 0) then
  begin
    ErrList.Add(sLineBreak + '- Network is empty.');
    exit;
  end;
  N := 0;
  for I := CONDUIT to OUTLET do
    N := N + Project.Lists[I].Count;
 if (N = 0) then
  begin
    ErrList.Add(sLineBreak + '- Network has no links.');
    exit;
  end;
  if Project.Lists[DIVIDER].Count > 0 then
  begin
    ErrList.Add(sLineBreak +
      '- Divider nodes detected. Please convert these to Junctions.');
    exit;
  end;
end;


procedure ValidateControls(LinkType: Integer; CtrlIndex: Integer; ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Validate parameters assigned to link controls.
//-----------------------------------------------------------------------------
var
  I, K : Integer;
  L : TLink;
  S : String;
begin
  with Project.Lists[LinkType] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      if SameText(L.Data[CtrlIndex], 'TIME') then
      begin
        S := L.Data[CtrlIndex + 1];
        K := Project.Lists[TIMESERIES].IndexOf(S);
        if K < 0 then
          ErrList.Add('- Control Time Series ' + S +
            ' used by Link ' + L.ID + ' does not exist.')
      end
      else if SameText(L.Data[CtrlIndex], 'DEPTH') then
      begin
        S := L.Data[CtrlIndex + 2];
        if GetNodeIndex(S) < 0 then
        begin
          ErrList.Add('- Control Node ' + S +
            ' used by Link ' + L.ID + ' does not exist.');
          continue;
        end;
        S := L.Data[CtrlIndex + 3];
        K := Project.Lists[CONTROLCURVE].IndexOf(S);
        if K < 0 then
          ErrList.Add('- Control Curve ' + S +
            ' used by Link ' + L.ID + ' does not exist.')
      end;
    end;
  end;
end;


procedure ValidateConduitShapes(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check that all pipes have circular shapes.
//-----------------------------------------------------------------------------
var
  I, Counter: Integer;
  L: TLink;
begin
    Counter := 0;
    with Project.Lists[CONDUIT] do
    begin
      for I := 0 to Count-1 do
      begin
       L := TLink(Objects[I]);
       if not SameText(L.Data[CONDUIT_SHAPE_INDEX], 'CIRCULAR') then
         Inc(Counter);
      end;
    end;
    if Counter > 0 then
    begin
      ErrList.Add(sLineBreak + '- ' + IntToStr(Counter) +
      ' non-circular conduits detected. ITM supports only circular pipes.')
    end;
end;


procedure ValidateStorageNodes(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check that all storage nodes have storage curves assigned.
//-----------------------------------------------------------------------------
var
  I, K: Integer;
  N: TNode;
  S: String;
begin
  with Project.Lists[STORAGE] do
  begin
    for I := 0 to Count-1 do
    begin
      N := TNode(Objects[I]);
      S := N.Data[STORAGE_ATABLE_INDEX];
      K := Project.Lists[STORAGECURVE].IndexOf(S);
      if K < 0 then
        ErrList.Add(sLineBreak + '- Storage Curve ' + S +
            ' used by Storage node ' + N.ID + ' does not exist.')
    end;
  end;
end;


procedure ValidatePumpLinks(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check that all pumps have a Type 5 pump curve assigned.
//-----------------------------------------------------------------------------
var
  I, K: Integer;
  L: TLink;
  C: TCurve;
  S: String;
begin
  with Project.Lists[PUMP] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      S := L.Data[PUMP_CURVE_INDEX];
      K := Project.Lists[PUMPCURVE].IndexOf(S);
      if K < 0 then
        ErrList.Add(sLineBreak + '- Pump Curve ' + S +
            ' used by Pump link ' + L.ID + ' does not exist.')
      else begin
        C := TCurve(Project.Lists[PUMPCURVE].Objects[K]);
        if not SameText(C.CurveType, 'PUMP5') then
           ErrList.Add(sLineBreak + '- Pump Curve ' + S +
            ' used by Pump link ' + L.ID + ' is not Type5');
      end;
    end;
  end;
end;


procedure ValidateOutletLinks(ErrList: TStringList);
//-----------------------------------------------------------------------------
// Check that all outlet links have a rating curve assigned.
//-----------------------------------------------------------------------------
var
  I, K: Integer;
  L: TLink;
  S: String;
begin
  with Project.Lists[OUTLET] do
  begin
    for I := 0 to Count-1 do
    begin
      L := TLink(Objects[I]);
      S := L.Data[OUTLET_QTABLE_INDEX];
      K := Project.Lists[RATINGCURVE].IndexOf(S);
      if K < 0 then
        ErrList.Add(sLineBreak + '- Rating Curve ' + S +
          ' used by Outlet link ' + L.ID + ' does not exist.')
    end;
  end;
end;


function GetInflow(I: Integer; aNode: TNode; TmpList, ErrList: TStringlist): String;
//-----------------------------------------------------------------------
// Extract inflow parameters from a node's DXInflow list of inflows.
// The FLOW entry in DXInflow is of form:
// 'FLOW' = Tseries #13 'FLOW' #13 '1.0' #13 ScaleFactor #13 BaseFlow
//-----------------------------------------------------------------------------
var
  J, N: Integer;
  TSeries, ScaleFactor, BaseFlow: String;

begin
  TSeries := '0';
  ScaleFactor := '0';
  BaseFlow := '0';
  Result := IntToStr(I+1) + Tab + '0' + Tab + '0' + Tab + '0';

  N := TmpList.Count;
  if N > 0 then
  begin
    TSeries := TmpList[0];
    if (Length(Tseries) > 0) then
    begin
      J := Project.Lists[TIMESERIES].IndexOf(Tseries);
      if J < 0 then
      begin
        ErrList.Add(sLineBreak + '- Inflow Time Series ' + Tseries +
          ' used by Junction ' + aNode.ID + ' does not exist.');
        exit;
      end;
    end
    else J := 0;
    Result := IntToStr(I+1) + Tab + IntToStr(J+1);

    if N > 3 then ScaleFactor := TmpList[3];
    if Length(ScaleFactor) = 0  then Scalefactor := '1';
    if N > 4 then BaseFlow := TmpList[4];
    if Length(BaseFlow) = 0 then BaseFlow := '0'
    else BaseFlow := ConvertUnits(BaseFlow, FlowCF);

    Result := Result + Tab + ScaleFactor + Tab + BaseFlow;
  end;
end;

procedure ValidateInflows(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check that all junction nodes have valid inflow parameters assigned.
//-----------------------------------------------------------------------------
var
  I, K: Integer;
  aNode: TNode;
  TmpList: TStringList;
  Line: String;
begin
  TmpList := TStringlist.Create;
  try
    with Project.Lists[JUNCTION] do
    begin
      for I := 0 to Count-1 do
      begin
        Line := IntToStr(I+1) + Tab + '0' + Tab + '0' + Tab + '0';
        aNode := TNode(Objects[I]);
        for K := 0 to aNode.DXInflow.Count-1 do
        begin
          if SameText(aNode.DXInflow.Names[K], 'FLOW') then
          begin
            TmpList.Clear;
            TmpList.SetText(PChar(aNode.DXInflow.Values[aNode.DXInflow.Names[K]]));
            Line := GetInflow(I, aNode, TmpList, ErrList);
            break;
          end;
        end;
        InflowList.Add(Line);
      end;
    end;
  finally
    TmpList.Free;
  end;
end;


procedure ValidateDates(ErrList: TStringlist);
//-----------------------------------------------------------------------------
// Check for consistent simulation start and end dates.
//-----------------------------------------------------------------------------
var
  StartDateTime: TDateTime;
  EndDateTime: TDateTime;
  ReportStart: TDateTime;
begin
   with Project.Options do
    begin
      StartDateTime := GetDateTime(Data[START_DATE_INDEX] + ' ' + Data[START_TIME_INDEX]);
      ReportStart := GetDateTime(Data[REPORT_START_DATE_INDEX] + ' ' +
                     Data[REPORT_START_TIME_INDEX]);
      EndDateTime := GetDateTime(Data[END_DATE_INDEX] + ' ' + Data[END_TIME_INDEX]);
      if EndDateTime <= StartDateTime then
        ErrList.Add(sLineBreak + '- Simulation starting date occurs after ending date.');
      if ReportStart < StartdateTime then
        ErrList.Add(sLineBreak + '- Report starting date occurs before simulation start date.');
    end;
end;


function ValidateProject : Boolean;
//-----------------------------------------------------------------------------
// Check that a valid ITM project can be built from the current SWMM project.
//-----------------------------------------------------------------------------
var
  ErrList : TStringList;
begin
  Result := True;
  ErrList := TStringList.Create;
  try
    ErrList.Add('ITM run canceled due to following errors:');
    ValidateNetwork(ErrList);
    ValidateConduitShapes(ErrList);
    ValidateStorageNodes(ErrList);
    ValidatePumpLinks(ErrList);
    ValidateOutletLinks(ErrList);
    ValidateControls(PUMP, PUMP_ITM_METHOD_INDEX, ErrList);
    ValidateControls(ORIFICE, ORIFICE_ITM_METHOD_INDEX, ErrList);
    ValidateControls(WEIR, WEIR_ITM_METHOD_INDEX, ErrList);
    ValidateInflows(ErrList);
    ValidateDates(ErrList);

    // Save error list to temporary report file
    if ErrList.Count > 1 then
    begin
      Result := False;
      ErrList.SaveToFile(Uglobals.TempReportFile);
    end;

  finally
    ErrList.Free;
  end;
end;


function  ExportItmProject(ItmFile, RunoffFile: String): Boolean;
//-----------------------------------------------------------------------------
// Create an ITM data set from the current SWMM project and save it to
// ItmFile. RunoffFile is the name of the SWMM runoff interface file
// that will provide inflows to the ITM simulation.
//-----------------------------------------------------------------------------
begin
  InflowList := TStringlist.Create;
  try
    // If a valid ITM project can be built then save it to file Fname
    Result := ValidateProject;
    if Result = True then SaveItmProject(ItmFile, RunoffFile);
  finally
    InflowList.Free;
  end;
end;

end.
