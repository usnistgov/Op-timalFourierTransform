function [freqs, MFT, fracErr] = MFT(g, t, f, bracket)
global flags
% dbstop if error     % TODO comment this out in production code
% Ported from VBA by Allen Goldstein, NIST from:
% http://jonova.s3.amazonaws.com/cfa/climate.xlsm
% written by: Dr David Evans
%             david.evans@sciencespeak.com
%
%===============================================================================================
%
% * Manual Fourier Transform for equally spaced time series.
% * "Manual" means that the exact Cosine/Sine frequencies to be calculated 
%     are pre-assumed before the MFT is called.
% * This is different from a DFT or FFT in that the frequencies of those 
%     are fixed based on the Extent and the sampling rate of the time series.
%
% * This code moves frequencies moves frequencies outside the Nyquist limit 
%    to inside the range (caution), removes frequecies that are very close to each other, 
%    and orders frequencies by amplitude.
%
% * Input:
%       g   [0..N-1]    Time series
%       t   [0..N-1]    Time of the data points (must be regular (equally spaced))
%       f   [1..nFreqs] Frequncies at which the MFT will assume their are frequencies
%       bracket [1..nBrackets] Number of frequencies per bracket.  If < 0, use only one bracket
%
% * Output:
%       freqs [1..nFreqs]   Frequencies with significant sinusoidsafter consolidation of close frequencies.
%                           note that this may be smaller than input "f[0..nFreqs]
%       MFT [1..nFreqs]     Complex MFT


%===============================================================================================%
% The below code is not part of the function call.  It returns handles to
% all the local subfunctions for the purpose of unit testing if the value
% of the "nu" input (normally a double) is the string '-test'
if ischar(g) && strcmp(g,'-test')
    MFT = 0+0i;
    fracErr = 0;
    freqs = localfunctions;
    return
end
%===============================================================================================%
% Constants
kRemoveFraction = 0.00000001;
%-------------------------------------------------------------------------------------------------------
kNuConsolidate = 0.1;   % How close should frequencies be allowed to get before they are consolidated
% Setting the consolidation distance:
%
%- Smaller naturally leads to greater discriminination between frequencies. Down to 0.002 tested ok.
%- Larger causes more consolidation of neighbouring frequencies, possibly gets waylaid in very local
%  maxima caused by two frequencies converging on same actual frequency. Seems to bve connected with number of iterations
%  allowed in MinimizeResidualByVaryingMultipleFreqs. Anyway, larger makes it better at finding frequencies
%  in synthesized time series. Tested up to 0.25 well.
%- Presuumably should set this based on how far apart sinusoids are expected in the time seires under analysis.
%- 0.08 seems like a good comporomise for the synthetics here.
%-------------------------------------------------------------------------------------------------------

t0 = t(1);              % first time in the series
Fs = 1/mean(diff(t));   % time series sample rate
E = t(end)-t0 + 1/Fs;   % Extent (the length of the series plus one/half sample period before and after)

nu_MFT = f * E;
tsV = g;


% The Optimal Fourier Transform process may send the MFT some freqs that are converging.  
% We need to identify and consolidate those freqs
if length(bracket) == 0 || any(bracket) < 0
    [nu_MFT,~] = ConsolidateFreqs(nu_MFT,kNuConsolidate);
else
    [nu_MFT, bracket] = ConsolidateFreqsByBracket (nu_MFT, bracket,kNuConsolidate);
end

kMaxNSAtOnce = length(nu_MFT);
%nuV = zeros(1,kMaxNSAtOnce);
nFreqsDone = 0;
bracketIx = 0;
nLeftThisBracket = 0;
freqs = [];
MFT = [];

while nFreqsDone < length(nu_MFT)
    nNuV = kMaxNSAtOnce;
    if ~isempty(bracket)        % Do all bracketing here
        if nLeftThisBracket == 0
            bracketIx = bracketIx + 1;
            if bracketIx <= length(bracket)
                nLeftThisBracket = bracket(bracketIx);
            else
                nLeftThisBracket = 99999;
            end
            if nNuV > nLeftThisBracket
                nNuV = nLeftThisBracket;
                nLeftThisBracket = 0;
            else
                nLeftThisBracket = nLeftThisBracket - nNuV;
            end
        end
    end
    
    nuV = zeros(1,bracket(bracketIx));
    for i=1:nNuV
        nuV(i) = nu_MFT(nFreqsDone + i);
    end
    
    [cosPart, sinPart] = EstimateContainedSinusoids (tsV,nuV);
%    [cosPart, sinPart] = EstimateContainedSinusoids (g,nuV);
    
    if nFreqsDone + nNuV < length(nu_MFT)
        [tsV, absDev] = SubtractMultipleSinusoidsFromTS(tsV, cosPart, sinPart, nuV);
    end
    
    %freqs = zeros(1,nNuV);
    for i = 1:nNuV
        nFreqsDone = nFreqsDone + 1;
        freqs(nFreqsDone) = nuV(i) / E;
        MFT(nFreqsDone) = complex(cosPart(i),sinPart(i));
    end
end
%nFreqs = nFreqsDone;
if isobject(flags)
    flags=flags.FlagHighAmplitudeSinusoids(g, length(ts), f, E, cosPart, sinPart);
end

[freqs, MFT] = SortSinusoidsByAmplitude (freqs, MFT, kRemoveFraction);

[fracErr] = FractionalError (g, E, freqs, MFT);

end

%============================== LOCAL FUNCTIONS ==========================%

function [nu_MFT, bracket] = ConsolidateFreqsByBracket(nu_MFT, bracket, kNuConsolidate)
% Consolidates converging frequencies but only within the same bracket

nu = nu_MFT;
nBrackets = length(bracket);
readBase = 0;
writeBase = 0;
Consolidated = false;

for bracketIx = 1:nBrackets
    nTemp = bracket(bracketIx);
    temp = zeros(1,nTemp);
    
    for i = 1:nTemp
        temp(i) = nu(readBase + i);     % Copy the freqs in the bracket to temp
    end
    readBase = readBase + nTemp;
    
    [temp,~] = ConsolidateFreqs(temp,kNuConsolidate);
    if length(temp)<nTemp
        for i = 1:length(temp)
            nu(writeBase+i) = temp(i);
        end
        Consolidated = true;
        bracket(bracketIx) = length(temp);
    else
        if Consolidated
            for i = 1:length(temp)
                nu(writeBase+i)=temp(i);
            end
        end
    end
    writeBase=writeBase+length(temp);   
end
nu_MFT = nu(1:writeBase);
end