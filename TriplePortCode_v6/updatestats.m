function [ stats ] = updatestats(stats,poke,pokeCount,syncFrame)
% [ stats ] = updatestats( pokeHistory )
% parses through one instance pokeHistory to update the pokeCount entry of
% stats
% 3/21/16 by shay neufeld
% 10/18/16 - modified by shay to incorporate syncing with inscopix.

%syncFrame
stats.sync_frame(pokeCount) = syncFrame;

%stats.time
stats.times(pokeCount) = now;


% isTRIAL == 0 means that the poke is 'incorrect' and not a trial
% isTRIAL == 1 means that centerPort has correctly initiated trial
% isTRIAL == 2 means that the poke is a decision poke

%stats.trials
if poke.isTRIAL == 2
    %if is.TRIAL == 2 then no error has been made only if pressed in center:
    stats.errors.right(pokeCount) = 0;
    stats.errors.left(pokeCount) = 0;
    stats.errors.center(pokeCount) = 0;
    %now correctly ascribe the trial:
    if strcmpi(poke.portPoked,'leftPort')
        stats.trials.left(pokeCount) = 2;
        stats.trials.right(pokeCount) = 0;
    elseif strcmpi(poke.portPoked,'rightPort')
        stats.trials.right(pokeCount) = 2;
        stats.trials.left(pokeCount) = 0;
    elseif strcmpi(poke.portPoked,'centerPort')
        % should never get here.
        stats.trials.left(pokeCount) = 0;
        stats.trials.right(pokeCount) = 0;
        stats.errors.center = 1;
    end
    %and finally determine if there was a reward:
    stats.rewards.left(pokeCount) = 0;
    stats.rewards.right(pokeCount) = 0;
    if poke.REWARD == 1
        if strcmpi(poke.portPoked,'leftPort')
            stats.rewards.left(pokeCount) = 1;
        elseif strcmpi(poke.portPoked,'rightPort')
            stats.rewards.right(pokeCount) = 1;
        end
    end

%stats.errors
elseif poke.isTRIAL == 0
    stats.trials.right(pokeCount) = 0;
    stats.trials.left(pokeCount) = 0;
    stats.rewards.right(pokeCount) = 0;
    stats.rewards.left(pokeCount) = 0;    
    if strcmpi(poke.portPoked,'leftPort')
        stats.errors.left(pokeCount) = 1;
        stats.errors.right(pokeCount) = 0;
        stats.errors.center(pokeCount) = 0;
    elseif strcmpi(poke.portPoked,'rightPort')
        stats.errors.right(pokeCount) = 1;
        stats.errors.left(pokeCount) = 0;
        stats.errors.center(pokeCount) = 0;
    elseif strcmpi(poke.portPoked,'centerPort')
        stats.errors.center(pokeCount) = 1;
        stats.errors.left(pokeCount) = 0;
        stats.errors.right(pokeCount) = 0;
    end
    
elseif poke.isTRIAL == 1
    %these are the trial initiations
        stats.trials.left(pokeCount) = 0;
        stats.trials.right(pokeCount) = 0;
% there are not errors:
        stats.errors.center(pokeCount) = 0;
        stats.errors.left(pokeCount) = 0;
        stats.errors.right(pokeCount) = 0;
%and there are no rewards for trial iniation:
        stats.rewards.left(pokeCount) = 0;
        stats.rewards.right(pokeCount) = 0;
end


