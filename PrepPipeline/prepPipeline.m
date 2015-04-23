function [EEG, computationTimes] = prepPipeline(EEG, params)
% Run the PREP pipeline for standardized EEG data preparation 
% 
% Input parameters:
%  EEG                       An EEGLAB structure with the data and chanlocs
%  params                    A structure with at least the following:
%
%     name                   A string with a name identifying dataset
%                            [default: EEG.setname]
%     referenceChannels      A vector of channels to be used for
%                            rereferencing [default: all channels]
%     evaluationChannels     A vector of channels to be used for
%                            EEG interpolation [default: all channels]
%     rereferencedChannels   A vector of channels to be  
%                            line-noise removed, and referenced
%                            [default: all channels]
%     lineFrequencies        A list of line frequencies to be removed
%                            [default: 60, 120, 180, 240]
%  
% Prep allows many other parameters to be over-ridden, but is meant to
% be used in a fully automated fashion.
%
% Output parameters:
%   EEG                      An EEGLAB structure with the data processed
%                            and status written in EEG.etc.noiseDetection
%   computationTimes         Time in seconds for each stage
%
% Additional setup:
%    EEGLAB should be in the path.
%    The EEG-Clean-Tools/PrepPipeline directory and its subdirectories 
%    should be in the path.
%
% Author:  Kay Robbins, UTSA, March 2015
%
% Full documentation is available in a user manual distributed with this
% source.

%% Setup the output structures and set the input parameters
computationTimes= struct('resampling', 0, 'globalTrend', 0,  ...
    'lineNoise', 0, 'reference', 0);
errorMessages = struct('status', 'good', 'boundary', 0, 'resampling', 0, ...
    'globalTrend', 0, 'detrend', 0, 'lineNoise', 0, 'reference', 0);
pop_editoptions('option_single', false, 'option_savetwofiles', false);
if isfield(EEG.etc, 'noiseDetection')
    warning('EEG.etc.noiseDetection already exists and will be cleared\n')
end
if ~exist('params', 'var')
    params = struct();
end
if ~isfield(params, 'name')
    params.name = ['EEG' EEG.filename];
end
EEG.etc.noiseDetection = ...
       struct('name', params.name, 'version', getPrepPipelineVersion, ...
              'errors', []);
%% Check for boundary events
try
    defaults = getPipelineDefaults(EEG, 'boundary');
    [boundaryOut, errors] = checkDefaults(params, struct(), defaults);
    if ~isempty(errors)
        error('boundary:BadParameters', ['|' sprintf('%s|', errors{:})]);
    end
    EEG.etc.noiseDetection.boundary = boundaryOut;
    if ~boundaryOut.ignoreBoundaryEvents && ...
            isfield(EEG, 'event') && ~isempty(EEG.event)
        eTypes = find(strcmpi({EEG.event.type}, 'boundary'));
        if ~isempty(eTypes)
            error(['Dataset ' params.name  ...
                ' has boundary events: [' getListString(eTypes) ...
                '] which are treated as discontinuities unless set to ignore']);
        end
    end
catch mex
    errorMessages.boundary = ...
        ['prepPipeline bad boundary events: ' getReport(mex)];
    errorMessages.status = 'unprocessed';
    EEG.etc.noiseDetection.errors = errorMessages;
    return;
end

%% Part I: Resampling
fprintf('Resampling\n');
try
    tic
    [EEG, resampling] = resampleEEG(EEG, params);
    EEG.etc.noiseDetection.resampling = resampling;
    computationTimes.resampling = toc;
catch mex
    errorMessages.resampling = ...
        ['prepPipeline failed resampleEEG: ' getReport(mex)];
    errorMessages.status = 'unprocessed';
    EEG.etc.noiseDetection.errors = errorMessages;
    return;
end

%% Part II:  HP the signal for detecting bad channels
fprintf('Preliminary detrend to compute reference\n');
try
    tic
    [EEGNew, detrend] = removeTrend(EEG, params);
    EEG.etc.noiseDetection.detrend = detrend;
    computationTimes.detrend = toc;
catch mex
    errorMessages.removeTrend = ...
        ['prepPipeline failed removeTrend: ' getReport(mex)];
    errorMessages.status = 'unprocessed';
    EEG.etc.noiseDetection.errors = errorMessages;
    return;
end
 
%% Part III: Remove line noise
fprintf('Line noise removal\n');
try
    tic
    [EEGClean, lineNoise] = cleanLineNoise(EEGNew, params);
    EEG.etc.noiseDetection.lineNoise = lineNoise;
    lineChannels = lineNoise.lineNoiseChannels;
    EEG.data(lineChannels, :) = EEG.data(lineChannels, :) ...
         - EEGNew.data(lineChannels, :) + EEGClean.data(lineChannels, :); 
    clear EEGNew;
    computationTimes.lineNoise = toc;
catch mex
    errorMessages.lineNoise = ...
        ['prepPipeline failed cleanLineNoise: ' getReport(mex)];
    errorMessages.status = 'unprocessed';
    EEG.etc.noiseDetection.errors = errorMessages;
    return;
end 

%% Part IV: Find reference
fprintf('Find reference\n');
try
    tic
    [EEG, referenceOut] = performReference(EEG, EEGClean, params);
    clear EEGClean;
    EEG.etc.noiseDetection.reference = referenceOut;
    computationTimes.reference = toc;
catch mex
    errorMessages.reference = ...
        ['prepPipeline failed performReference: ' ...
        getReport(mex, 'basic', 'hyperlinks', 'off')];
    errorMessages.status = 'unprocessed';
    EEG.etc.noiseDetection.errors = errorMessages;
    return;
end

%% Report that there were no errors
EEG.etc.noiseDetection.errors = errorMessages;

