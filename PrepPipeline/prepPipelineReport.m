%% Visualize the EEG output from the PREP processing pipeline.
%
% Calling directly:
%      prepPipelineReport
%
% This helper reporting script expects that EEG will be in the base workspace
% with an EEG.etc.noiseDetection structure containing the report. It
% also expects the following variables in the base workspace:
% 
% * summaryReportName name of the summary report
% * summaryFolder folder where summary report goes
% * sessionFolder folder where specific report goes
% * sessionReportName name of individual report
% * relativeReportLocation report location relative to summary
%
% The reporting function appends a summary to the summary report. 
%
% Usually the prepPipelineReport script is called through the function:
%
%        publishPrepPipelineReport 
%
%% Write data status and report header
noiseDetection = EEG.etc.noiseDetection;
if isfield(noiseDetection, 'reference')
    reference = noiseDetection.reference;
else
    reference = struct();
end
summaryHeader = [noiseDetection.name '[' ...
    num2str(size(EEG.data, 1)) ' channels, ' num2str(size(EEG.data, 2)) ' frames]'];
summaryHeader = [summaryHeader ' <a href="' relativeReportLocation ...
    '">Report details</a>'];
writeSummaryHeader(summaryFile,  summaryHeader);

%  Write overview status
writeSummaryItem(summaryFile, '', 'first');
errorStatus = ['Error status: ' noiseDetection.errors.status];

fprintf(consoleFID, '%s \n', errorStatus);
writeSummaryItem(summaryFile, {errorStatus});

% Versions
versions = EEG.etc.noiseDetection.version;
versionString = getStructureString(EEG.etc.noiseDetection.version);
writeSummaryItem(summaryFile, {['Versions: ' versionString]});
fprintf(consoleFID, 'Versions:\n%s\n', versionString);

% Events
srateMsg = ['Sampling rate: ' num2str(EEG.srate) 'Hz'];
writeSummaryItem(summaryFile, {srateMsg});
fprintf(consoleFID, '%s\n', srateMsg);
[summary, hardFrames] = reportEvents(consoleFID, EEG);
writeSummaryItem(summaryFile, summary);

% Interpolated channels for referencing
if isfield(noiseDetection, 'reference')
    interpolatedChannels = getFieldIfExists(noiseDetection, ...
        'interpolatedChannels');
    summaryItem = ['Bad channels interpolated for reference: [' ...
                    num2str(interpolatedChannels), ']'];
    writeSummaryItem(summaryFile, {summaryItem});
    fprintf(consoleFID, '%s\n', summaryItem);
end
% Setup visualization parameters
numbersPerRow = 10;
indent = '  ';
colors = [0, 0, 0; 1, 0, 0; 0, 1, 0];
legendStrings = {'Original', 'Final'};
scalpMapInterpolation = 'v4';

%% Global trend removal step
summary = reportGlobalDetrend(consoleFID, noiseDetection, numbersPerRow, indent);
writeSummaryItem(summaryFile, summary);

%% Line noise removal step
summary = reportLineNoise(consoleFID, noiseDetection, numbersPerRow, indent);
writeSummaryItem(summaryFile, summary);

%% Initial detrend for reference calculation
summary = reportDetrend(consoleFID, noiseDetection, numbersPerRow, indent);
writeSummaryItem(summaryFile, summary);

%% Trend correlation evaluation channels relationships 
if isfield(noiseDetection, 'globalTrend')
  channels = noiseDetection.globalTrend.globalTrendChannels;
  tString = 'Global trend (trend channels)';
  if isfield(noiseDetection, 'reference')
      channels = intersect(channels, noiseDetection.reference.evaluationChannels);
      tString = 'Global trend (evaluation channels)';
  end
  fits = noiseDetection.globalTrend.linearFit(channels, :);
  correlations = noiseDetection.globalTrend.channelCorrelations(channels);
  showTrendCorrelation(fits, correlations, tString);
else
    fprintf(consoleFID, 'Global trend not evaluated\n');
    EEGNew = EEG;
end

%% Spectrum after line noise and detrend
if isfield(noiseDetection, 'lineNoise')
    lineChannels = noiseDetection.lineNoise.lineNoiseChannels; 
    numChans = min(6, length(lineChannels));
    indexchans = floor(linspace(1, length(lineChannels), numChans));
    displayChannels = lineChannels(indexchans);
    channelLabels = {EEG.chanlocs(lineChannels).labels};
    tString = noiseDetection.name;
    if isfield(noiseDetection, 'detrend') 
       EEGNew = removeTrend(EEG, noiseDetection.detrend);
    else
       EEGNew = EEG;
    end
    [fref, sref, badChannels] = showSpectrum(EEGNew, channelLabels, ...
        lineChannels, displayChannels, tString);
    clear EEGNew;
    if ~isempty(badChannels)
        badString = ['Channels with no spectra: ' getListString(badChannels)];
        fprintf(consoleFID, '%s\n', badString);
        writeSummaryItem(summaryFile, {badString});
    end
end


%% Report referencing step
if isfield(noiseDetection, 'reference') && ~isempty(noiseDetection.reference) 
   [summary, noisyStatistics] = reportReference(consoleFID,  ...
                                  noiseDetection, numbersPerRow, indent);
    writeSummaryItem(summaryFile, summary);
   EEG.etc.noiseDetection.reference.noisyStatistics = noisyStatistics;
end
%% Robust channel deviation (referenced)
if isfield(noiseDetection, 'reference') && ~isempty(noiseDetection.reference) 
    reference = noiseDetection.reference;
    headColor = [0.7, 0.7, 0.7];
    elementColor = [0, 0, 0];
    showColorbar = true;   
    channelInformation = reference.channelInformation;
    nosedir = channelInformation.nosedir;
    channelLocations = reference.channelLocations;
    [referencedLocations, evaluationChannels, noiseLegendString]= ...
        getReportChannelInformation(channelLocations, noisyStatistics);
    if ~isfield(reference, 'noisyStatisticsOriginal') || ...
            isempty(reference.noisyStatisticsOriginal)
        noisyStatisticsOriginal = noisyStatistics;
    else
        noisyStatisticsOriginal = reference.noisyStatisticsOriginal;
    end
    fprintf(consoleFID, 'No original statistics --- using final for both\n');
    originalLocations = getReportChannelInformation(channelLocations, ...
        noisyStatisticsOriginal);
    numberEvaluationChannels = length(evaluationChannels);
    tString = 'Robust channel deviation';
    dataReferenced = noisyStatistics.robustChannelDeviation;
    dataOriginal = noisyStatisticsOriginal.robustChannelDeviation;
    medRef = noisyStatistics.channelDeviationMedian;
    sdnRef = noisyStatistics.channelDeviationSD;
    medOrig = noisyStatisticsOriginal.channelDeviationMedian;
    sdnOrig = noisyStatisticsOriginal.channelDeviationSD;
    scale = max(max(abs(dataOriginal), max(abs(dataReferenced))));
    clim = [-scale, scale];    
    fprintf(consoleFID, '\nNoisy channel legend: ');
    for j = 1:length(noiseLegendString)
        fprintf(consoleFID, '%s ', noiseLegendString{j});
    end
    fprintf(consoleFID, '\n\n');
    plotScalpMap(dataReferenced, referencedLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(referenced)'])
end 

%% Robust channel deviation (original)
if isfield(noiseDetection, 'reference')
    plotScalpMap(dataOriginal, originalLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(original)'])
end  

%% Robust deviation window statistics
if isfield(noiseDetection, 'reference')
    beforeDeviationLevels = noisyStatisticsOriginal.channelDeviations(evaluationChannels, :);
    afterDeviationLevels = noisyStatistics.channelDeviations(evaluationChannels, :);
    beforeDeviation = (beforeDeviationLevels - medOrig)./sdnOrig;
    afterDeviation = (afterDeviationLevels - medRef)./sdnRef;
    medianDeviationsOrig = median(beforeDeviationLevels(:));
    sdDeviationsOrig = mad(beforeDeviationLevels(:), 1)*1.4826;
    medianDeviationsRef = median(afterDeviationLevels(:));
    sdDeviationsRef = mad(afterDeviationLevels(:), 1)*1.4826;
    thresholdName = 'Deviation score';
    theTitle = {char(noiseDetection.name); char([ thresholdName ' distribution'])};
    showCumulativeDistributions({beforeDeviation(:), afterDeviation(:)}, ...
        thresholdName, colors, theTitle, legendStrings, [-5, 5]);
    beforeDeviationCounts = sum(beforeDeviation >= noisyStatisticsOriginal.robustDeviationThreshold);
    afterDeviationCounts = sum(afterDeviation >= noisyStatistics.robustDeviationThreshold);
 
    beforeTimeScale = (0:length(beforeDeviationCounts)-1)*noisyStatisticsOriginal.correlationWindowSeconds;
    afterTimeScale = (0:length(afterDeviationCounts)-1)*noisyStatistics.correlationWindowSeconds;
    fractionBefore = mean(beforeDeviationCounts)/numberEvaluationChannels;
    fractionAfter = mean(afterDeviationCounts)/numberEvaluationChannels;
    showBadWindows(beforeDeviationCounts, afterDeviationCounts, beforeTimeScale, afterTimeScale, ...
        numberEvaluationChannels, legendStrings, noiseDetection.name, thresholdName);
    reports = cell(19, 1);
    reports{1} = ['Deviation window statistics (over ' ...
        num2str(size(noisyStatistics.channelDeviations, 2)) ' windows)'];
    reports{2} = 'Large deviation channel fraction:';
    reports{3} = [indent ' [before=', ...
        num2str(fractionBefore) ', after=' num2str(fractionAfter) ']'];
    reports{4} = ['Median channel deviation: [before=', ...
        num2str(noisyStatisticsOriginal.channelDeviationMedian) ...
        ', after=' num2str(noisyStatistics.channelDeviationMedian) ']'];
    reports{5} = ['SD channel deviation: [before=', ...
        num2str(noisyStatisticsOriginal.channelDeviationSD) ...
        ', after=' num2str(noisyStatistics.channelDeviationSD) ']'];
    reports{6} = ['Max raw deviation level [before=', ...
        num2str(max(beforeDeviationLevels(:))) ', after=' ...
        num2str(max(afterDeviationLevels(:))) ']'];
    reports{7} = ['Average fraction ' num2str(fractionBefore) ...
               ' (' num2str(mean(beforeDeviationCounts)) ' channels)']; 
    reports{8}= [indent ' not meeting threshold before in each window'];
    reports{9} = ['Average fraction ' num2str(fractionAfter) ...
               ' (' num2str(mean(afterDeviationCounts)) ' channels)'];
    reports{10} = [ indent ' not meeting threshold after in each window'];
    quarterChannels = round(length(evaluationChannels)*0.25);
    halfChannels = round(length(evaluationChannels)*0.5);
    reports{11} = 'Windows with > 1/4 deviation channels:';
    reports{12} = [indent '[before=' ...
           num2str(sum(beforeDeviationCounts > quarterChannels)) ...
        ', after=' num2str(sum(afterDeviationCounts > quarterChannels)) ']'];
    reports{13} = 'Windows with > 1/2 deviation channels:';
    reports{14} = [indent '[before=', ...
        num2str(sum(beforeDeviationCounts > halfChannels)) ...
        ', after=' num2str(sum(afterDeviationCounts > halfChannels))  ']'];
    reports{15} = ['Median window deviations: [before=', ...
              num2str(medianDeviationsOrig) ', after=' num2str(medianDeviationsRef) ']'];
    reports{16} = ['SD window deviations: [before=', ...
        num2str(sdDeviationsOrig) ', after=' num2str(sdDeviationsRef) ']'];
    if isfield(noisyStatistics, 'dropOuts')
        drops = sum(noisyStatistics.dropOuts, 2)';
        indexDrops = find(drops > 0);
        dropList = [indexDrops; drops(indexDrops)];
        if ~isempty(indexDrops) > 0
            reportString = sprintf('%g[%g drops] ', dropList(:)');
        else
            reportString = 'None';
        end
        reports{17} = ['Channels with dropouts: ' reportString];
    end
    fprintf(consoleFID, '%s:\n', reports{1});
    for k = 2:length(reports)
        fprintf(consoleFID, '%s\n', reports{k});
    end
    writeSummaryItem(summaryFile, {reports{1}, reports{2}, reports{3}});
end    

%% Median max abs correlation (referenced)
if isfield(noiseDetection, 'reference')
    tString = 'Median max correlation';
    dataReferenced = noisyStatistics.medianMaxCorrelation;
    clim = [0, 1];
    plotScalpMap(dataReferenced, referencedLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(referenced)'])
end 

%% Median max abs correlation (original)
if isfield(noiseDetection, 'reference')
    tString = 'Median max correlation';
    dataOriginal = noisyStatisticsOriginal.medianMaxCorrelation;
    clim = [0, 1];
    plotScalpMap(dataOriginal, originalLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(original)'])
end 


%% Mean max abs correlation (referenced)
if isfield(noiseDetection, 'reference')
    tString = 'Mean max correlation';
    dataReferenced = mean(noisyStatistics.maximumCorrelations, 2); 
    clim = [0, 1];
    plotScalpMap(dataReferenced, referencedLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(referenced)'])
end

%% Mean max abs correlation (original)
if isfield(noiseDetection, 'reference')
    tString = 'Mean max correlation';
    dataOriginal = mean(noisyStatisticsOriginal.maximumCorrelations, 2); 
    clim = [0, 1];
    plotScalpMap(dataOriginal, originalLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(original)'])
end  
%% Correlation window statistics
if isfield(noiseDetection, 'reference')
    beforeCorrelationLevels = noisyStatisticsOriginal.maximumCorrelations(evaluationChannels, :);
    afterCorrelationLevels = noisyStatistics.maximumCorrelations(evaluationChannels, :);
    thresholdName = 'Maximum correlation';
    theTitle = {char(noiseDetection.name); char([thresholdName ' distribution'])};
    showCumulativeDistributions({beforeCorrelationLevels(:), afterCorrelationLevels(:)}, ...
        thresholdName, colors, theTitle, legendStrings, [0, 1]);
    
    beforeCorrelationCounts = sum(beforeCorrelationLevels <= ...
        noisyStatisticsOriginal.correlationThreshold);
    afterCorrelationCounts = sum(afterCorrelationLevels <= ...
        noisyStatistics.correlationThreshold);
    beforeTimeScale = (0:length(beforeCorrelationCounts)-1)* ...
        noisyStatisticsOriginal.correlationWindowSeconds;
    afterTimeScale = (0:length(afterCorrelationCounts)-1)* ...
        noisyStatistics.correlationWindowSeconds;
    showBadWindows(beforeCorrelationCounts, afterCorrelationCounts, ...
        beforeTimeScale, afterTimeScale, ...
        numberEvaluationChannels, legendStrings, noiseDetection.name, thresholdName);
    fractionBefore = mean(beforeCorrelationCounts)/numberEvaluationChannels;
    fractionAfter = mean(afterCorrelationCounts)/numberEvaluationChannels;
    reports = cell(10, 1);
    reports{1} = ['Max correlation window statistics (over ' ...
        num2str(size(noisyStatistics.maximumCorrelations, 2)) ' windows)'];
    reports{2} = ['Overall median maximum correlation [before=', ...
        num2str(median(noisyStatisticsOriginal.medianMaxCorrelation(:))) ...
        ', after=' num2str(median(noisyStatistics.medianMaxCorrelation(:))) ']'];
    reports{3} = ['Low max correlation fraction [before=', ...
        num2str(fractionBefore) ', after=' num2str(fractionAfter) ']'];
    reports{4} = ['Minimum max correlation level [before=', ...
        num2str(min(beforeCorrelationLevels(:))) ', after=' ...
        num2str(min(afterCorrelationLevels(:))) ']'];
    reports{5} = ['Average fraction ' num2str(fractionBefore) ...
               ' (' num2str(mean(beforeCorrelationCounts)) ' channels):']; 
    reports{6} =  [indent ' not meeting threshold before in each window'];
    reports{7} = ['Average fraction ' num2str(fractionAfter) ...
               ' (' num2str(mean(afterCorrelationCounts)) ' channels):'];
    reports{8} = [indent ' not meeting threshold after in each window'];
    quarterChannels = round(length(evaluationChannels)*0.25);
    halfChannels = round(length(evaluationChannels)*0.5);
    reports{9} = ['Windows with > 1/4 bad channels: [before=', ...
        num2str(sum(beforeCorrelationCounts > quarterChannels)) ...
        ', after=' num2str(sum(afterCorrelationCounts > quarterChannels)) ']'];
    reports{10} = ['Windows with > 1/2 bad channels: [before=', ...
        num2str(sum(beforeCorrelationCounts > halfChannels)) ...
        ', after=' num2str(sum(afterCorrelationCounts > halfChannels)) ']'];
    fprintf(consoleFID, '%s:\n', reports{1});
    for k = 2:length(reports)
        fprintf(consoleFID, '%s\n', reports{k});
    end
    writeSummaryItem(summaryFile, {reports{1}, reports{2}});
end

%% Bad ransac fraction (referenced)
if isfield(noiseDetection, 'reference')
    tString = 'Ransac fraction failed';
    dataReferenced = noisyStatistics.ransacBadWindowFraction;

    clim = [0, 1];
    
    plotScalpMap(dataReferenced, referencedLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(referenced)'])
end    
%% Bad ransac fraction (original)
if isfield(noiseDetection, 'reference')
        dataOriginal = noisyStatisticsOriginal.ransacBadWindowFraction;
    plotScalpMap(dataOriginal, originalLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(original)'])
end    
%% Channels with poor ransac correlations
if isfield(noiseDetection, 'reference')
    beforeRansacLevels = noisyStatisticsOriginal.ransacCorrelations(evaluationChannels, :);
    afterRansacLevels = noisyStatistics.ransacCorrelations(evaluationChannels, :);
    thresholdName = 'Ransac correlation';
    theTitle = {char([noiseDetection.name ': ' thresholdName ' distribution'])};
    showCumulativeDistributions({beforeRansacLevels(:), afterRansacLevels(:)}, ...
        thresholdName, colors, theTitle, legendStrings, [0, 1]);
    
    beforeRansacCounts = sum(beforeRansacLevels <= ...
        noisyStatisticsOriginal.ransacCorrelationThreshold);
    afterRansacCounts = sum(afterRansacLevels <= ...
        noisyStatistics.ransacCorrelationThreshold);
    beforeTimeScale = (0:length(beforeRansacCounts)-1)* ...
        noisyStatisticsOriginal.ransacWindowSeconds;
    afterTimeScale = (0:length(afterRansacCounts)-1)* ...
        noisyStatisticsOriginal.ransacWindowSeconds;
    showBadWindows(beforeRansacCounts, afterRansacCounts, beforeTimeScale, afterTimeScale, ...
        numberEvaluationChannels, legendStrings, noiseDetection.name, thresholdName);
    fractionBefore = mean(beforeRansacCounts)/numberEvaluationChannels;
    fractionAfter = mean(afterRansacCounts)/numberEvaluationChannels;
    reports = cell(9, 0);
    reports{1} = ['Ransac window statistics (over ' ...
        num2str(size(afterRansacLevels, 2)) ' windows)'];
    reports{2} = ['Low ransac channel fraction [before=', ...
        num2str(fractionBefore) ', after=' num2str(fractionAfter) ']'];
    reports{3} = ['Minimum ransac correlation [before=', ...
        num2str(min(beforeRansacLevels(:))) ', after=' ...
        num2str(min(afterRansacLevels(:))) ']'];
    reports{4} = ['Average fraction ' num2str(fractionBefore) ...
               ' (' num2str(mean(beforeRansacCounts)) ' channels):'];
    reports{5} = [indent ' not meeting threshold before in each window'];
    reports{6} = ['Average fraction ' num2str(fractionAfter) ...
               ' (' num2str(mean(afterRansacCounts)) ' channels):'];
    reports{7} = [indent ' not meeting threshold after in each window'];
    quarterChannels = round(length(evaluationChannels)*0.25);
    halfChannels = round(length(evaluationChannels)*0.5);
    reports{8} = ['Windows with > 1/4 bad ransac channels: [before=', ...
        num2str(sum(beforeRansacCounts > quarterChannels)) ...
        ', after=' num2str(sum(afterRansacCounts > quarterChannels)) ']'];
    reports{9} = ['Windows with > 1/2 bad ransac channels: [before=', ...
        num2str(sum(beforeRansacCounts > halfChannels)) ...
        ', after=' num2str(sum(afterRansacCounts > halfChannels)) ']'];
    fprintf(consoleFID, '%s:\n', reports{1});
    for k = 2:length(reports)
        fprintf(consoleFID, '%s\n', reports{k});
    end
    writeSummaryItem(summaryFile, {reports{1}, reports{2}});
end    
%% HF noise Z-score (referenced)
if isfield(noiseDetection, 'reference')
    tString = 'Z-score HF SNR';
    dataReferenced = noisyStatistics.zscoreHFNoise;
    dataOriginal = noisyStatisticsOriginal.zscoreHFNoise;
    medRef = noisyStatistics.noisinessMedian;
    sdnRef = noisyStatistics.noisinessSD;
    medOrig = noisyStatisticsOriginal.noisinessMedian;
    sdnOrig = noisyStatisticsOriginal.noisinessSD;
    scale = max(max(abs(dataReferenced), max(abs(dataOriginal))));
    clim = [-scale, scale];  
    plotScalpMap(dataReferenced, referencedLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(referenced)'])
end  
%% HF noise Z-score (original)
if isfield(noiseDetection, 'reference')
    plotScalpMap(dataOriginal, originalLocations, scalpMapInterpolation, ...
        showColorbar, headColor, elementColor, clim, nosedir, [tString '(original)'])
end

%% HF noise window stats
if isfield(noiseDetection, 'reference')
    beforeNoiseLevels = noisyStatisticsOriginal.noiseLevels(evaluationChannels, :);
    afterNoiseLevels = noisyStatistics.noiseLevels(evaluationChannels, :);
    medianNoiseOrig = median(beforeNoiseLevels(:));
    sdNoiseOrig = mad(beforeNoiseLevels(:), 1)*1.4826;
    medianNoiseRef = median(afterNoiseLevels(:));
    sdNoiseRef = mad(afterNoiseLevels(:), 1)*1.4826;
    beforeNoise = (beforeNoiseLevels - medianNoiseOrig)./sdNoiseOrig;
    afterNoise = (afterNoiseLevels - medianNoiseRef)./sdNoiseRef;
    thresholdName = 'HF noise';
    theTitle = {char(noiseDetection.name); [thresholdName ' HF noise distribution']};
    showCumulativeDistributions({beforeNoise(:), afterNoise(:)},  ...
        thresholdName, colors, theTitle, legendStrings, [-5, 5]);
    beforeNoiseCounts = sum(beforeNoise  >= ...
        noisyStatisticsOriginal.highFrequencyNoiseThreshold);
    afterNoiseCounts = sum(afterNoise >= ...
        noisyStatistics.highFrequencyNoiseThreshold);
   
    beforeTimeScale = (0:length(beforeNoiseCounts)-1)* ...
        noisyStatisticsOriginal.correlationWindowSeconds;
    afterTimeScale = (0:length(afterNoiseCounts)-1)* ...
        noisyStatistics.correlationWindowSeconds;
    showBadWindows(beforeNoiseCounts, afterNoiseCounts, beforeTimeScale, afterTimeScale, ...
        length(evaluationChannels), legendStrings, noiseDetection.name, thresholdName);
    
    fractionBefore = mean(beforeNoiseCounts)/numberEvaluationChannels;
    fractionAfter = mean(afterNoiseCounts)/numberEvaluationChannels;
    reports = cell(17,0);
    reports{1} = ['Noise window statistics (over ' ...
        num2str(size(noisyStatistics.noiseLevels, 2)) ' windows)'];
    reports{2} = 'Channel fraction with HF noise:';
    reports{3} = [indent '[before=', ...
                  num2str(fractionBefore) ', after=' num2str(fractionAfter) ']'];
    reports{4} = ['Median noisiness: [before=', ...
        num2str(noisyStatisticsOriginal.noisinessMedian) ...
        ', after=' num2str(noisyStatistics.noisinessMedian) ']'];
    reports{5} = ['SD noisiness: [before=', ...
        num2str(noisyStatisticsOriginal.noisinessSD) ...
        ', after=' num2str(noisyStatistics.noisinessSD) ']'];
    reports{6} = ['Max HF noise levels [before=', ...
        num2str(max(beforeNoiseLevels(:))) ', after=' ...
        num2str(max(afterNoiseLevels(:))) ']'];
    reports{7} = ['Average fraction ' num2str(fractionBefore) ...
                ' (' num2str(mean(beforeNoiseCounts)) ' channels):'];
    reports{8} = [indent ' not meeting threshold before in each window'];
    reports{9} = ['Average fraction ' num2str(fractionAfter) ...
               ' (' num2str(mean(afterNoiseCounts)) ' channels):'];
    reports{10} = [indent ' not meeting threshold after in each window'];
    reports{11} = [indent ' not meeting threshold after relative to before in each window'];
    quarterChannels = round(length(evaluationChannels)*0.25);
    halfChannels = round(length(evaluationChannels)*0.5);
    reports{12} = 'Windows with > 1/4 HF channels:';
    reports{13} = [indent '[before=', ...
        num2str(sum(beforeNoiseCounts > quarterChannels)) ...
        ', after=' num2str(sum(afterNoiseCounts > quarterChannels)) ']'];
    reports{14} = 'Windows with > 1/2 HF channels:';
    reports{15} = [indent '[before=', ...
        num2str(sum(beforeNoiseCounts > halfChannels)) ...
        ', after=' num2str(sum(afterNoiseCounts > halfChannels)) ']'];
    reports{16} = ['Median window HF: [before=', ...
        num2str(medianNoiseOrig) ', after=' num2str(medianNoiseRef) ']'];
    reports{17} = ['SD window HF: [before=', ...
        num2str(sdNoiseOrig) ', after=' num2str(sdNoiseRef) ']'];
     fprintf(consoleFID, '%s:\n', reports{1});
    for k = 2:length(reports)
        fprintf(consoleFID, '%s\n', reports{k});
    end
    writeSummaryItem(summaryFile, {reports{1}, reports{2}, reports{3}});
end


%% Noisy average reference vs robust average reference
if isfield(noiseDetection, 'reference') && ...
        isfield(reference, 'referenceSignal') && ...
        ~isempty(reference.referenceSignal)
    corrAverage = corr(reference.referenceSignal(:), ...
               reference.referenceSignalOriginal(:));
    tString = { noiseDetection.name, ...
        ['Comparison of reference signals (corr=' num2str(corrAverage) ')']};
    figure('Name', tString{2})
    plot(reference.referenceSignal, reference.referenceSignalOriginal, '.k');
    xlabel('Robust average reference')
    ylabel('Ordinary average reference');
    title(tString, 'Interpreter', 'None');
    writeSummaryItem(summaryFile, ...
        {['Correlation between ordinary and robust average reference (unfiltered): ' ...
        num2str(corrAverage)]});
end   
%% Noisy average reference - robust average reference by time
if isfield(noiseDetection, 'reference') && ...
    isfield(reference, 'referenceSignal') && ...
     ~isempty(reference.referenceSignal)
    tString = { noiseDetection.name, 'ordinary - robust average reference signals'};
    t = (0:length(reference.referenceSignal) - 1)/EEG.srate;
    figure('Name', tString{2})
    plot(t, reference.referenceSignalOriginal - reference.referenceSignal, '.k');
    xlabel('Seconds')
    ylabel('Original - robust');
    title(tString, 'Interpreter', 'None');
end

%% Noisy average reference vs robust average reference (filtered)
if isfield(noiseDetection, 'reference')
    EEGTemp = eeg_emptyset();
    EEGTemp.nbchan = 2;
    a = reference.referenceSignalOriginal;
    b = reference.referenceSignal;
    EEGTemp.pnts = length(a);
    EEGTemp.data = [a(:)'; b(:)'];
    EEGTemp.srate = EEG.srate;
    EEGTemp = pop_eegfiltnew(EEGTemp, noiseDetection.detrend.detrendCutoff, []);
    corrAverage = corr(EEGTemp.data(1, :)', EEGTemp.data(2, :)');
    tString = { noiseDetection.name, ...
        ['Comparison of reference signals (corr=' num2str(corrAverage) ')']};
    figure('Name', tString{2})
    plot(EEGTemp.data(1, :),  EEGTemp.data(2, :), '.k');
    xlabel('Robust average reference')
    ylabel('Ordinary average reference');
    title(tString, 'Interpreter', 'None');
    writeSummaryItem(summaryFile, ...
        {['Correlation between ordinary and robust average reference (filtered): ' ...
        num2str(corrAverage)]});
end
%% Noisy average reference - robust average reference by time
if isfield(noiseDetection, 'reference') 
    tString = { noiseDetection.name, 'ordinary - robust average reference signals'};
    t = (0:length(EEGTemp.data(2, :)) - 1)/EEG.srate;
    figure('Name', tString{2})
    plot(t, EEGTemp.data(1, :) - EEGTemp.data(2, :), '.k');
    xlabel('Seconds')
    ylabel('Average - robust');
    title(tString, 'Interpreter', 'None');
end