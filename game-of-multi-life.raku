#!/usr/bin/env raku
#`<<
    A GoL in Raku
    Written by: Amplee
    Date: 2025-05-19
>>

use JSON::Fast;
use MIDI::Make;

# Global variables
my @grid;
my $generation = 0;
my $scale-offset = 0;
my %scale-letter-to-offset = (
    "A"  =>  0,
    "A#" =>  1,
    "Bb" =>  1,
    "B"  =>  2,
    "C"  =>  3,
    "C#" =>  4,
    "Db" =>  4,
    "D"  =>  5,
    "D#" => -6,
    "Eb" => -6,
    "E"  => -5,
    "F"  => -4,
    "F#" => -3,
    "Gb" => -3,
    "G"  => -2,
    "G#" => -1,
    "Ab" => -1,
);

my $sleep-time //= 0.04;
my $midi-file = "midi/gol-output-" ~ time.Str ~ ".mid";
my $no-midi = False;
my $song = MIDI::Make::Song.new(:PPQ(96), :format(0));
my $track = MIDI::Make::Track.new;
$track.tempo: ♩174;

#`[[
    Append the current grid state to the MIDI file using a Janko-inspired
    layout
]]
sub gol_grid-append-to-midi(@grid) {
    my $velocity = 64;
    my $note-length = 48;

    # Define a scale:
    # pentatonic scales
    my @scale1 = (0, 3, 5, 7, 10);
    my @scale2 = (3, 5, 7, 10, 0);
    my @scale3 = (5, 7, 10, 0, 3);
    my @scale4 = (7, 10, 0, 3, 5);
    my $base-note = 33 + $scale-offset;
    my $max-octave = 5;

    # Map a (row, col) position to a scale-based MIDI note
    sub janko-scale-note(Int $row, Int $col --> UInt) {
        my $index = $col + $row * 5;

        # choose a different scale each (4,8,12,16) generations:
        my $scale-index = ($generation div (4, 8, 12, 16).pick % 4);
        my @scale = do given $scale-index {
            when 0 { @scale1 }
            when 1 { @scale2 }
            when 2 { @scale3 }
            when 3 { @scale4 }
        };
        my $note-in-scale = @scale[$index % @scale.elems];
        my $octave = ($index div @scale.elems);
        $octave = $max-octave if $octave > $max-octave;

        return ($base-note + 12 * $octave + $note-in-scale) min 127;
    }

    # Build list of active notes (each cell becomes a note if alive)
    my %seen;
    my @notes = gather for @grid.kv -> $row-idx, @row {
        for @row.kv -> $col-idx, $v {
            if $v {
                my $note = janko-scale-note($row-idx, $col-idx);
                unless %seen{$note} {
                    take $note;
                    %seen{$note} = True;
                }
            }
        }
    }

    # Play the notes with a "strum" effect to avoid full block chords
    if @notes {
        my $strum-length = ($note-length / @notes.elems).UInt;
        for @notes -> UInt $note {
            $track.note-on($note, $velocity);
            $track.delta-time($strum-length);
        }

        # Wait before turning off the notes
        $track.delta-time(2 * $strum-length);

        for @notes -> UInt $note {
            $track.note-off($note, 0);
        }
    } else {
        # No live cells: write a rest
        $track.delta-time($note-length);
    }
}

#`[[
    Parse a json file into a grid
]]
sub gol_parse-json($json-path) {
    return from-json slurp($json-path);
}

#`[[
    Generate a grid of size $m x $n with $population % of cells alive
]]
sub gol_grid($m, $n, $population) {
    my $total-cells = $m * $n;
    my $alive-cells = ($total-cells * $population / 100).Int;

    # Initialize the grid with dead cells
    for 0 ..^ $m -> $i {
        @grid[$i] = [ 0 xx $n ];
    }

    # Randomly place alive cells according to population percentage
    while $alive-cells > 0 {
        my $i = (0..^$m).pick;
        my $j = (0..^$n).pick;
        unless @grid[$i][$j] {
            @grid[$i][$j] = (1..2).pick;
            $alive-cells--;
        }
    }

    return @grid;
}

#`[[
    Count neighbors of a cell at (i, j)
]]
sub gol_neighbors($grid, $i, $j, $id) {
    my $neighbors = 0;
    my $rows = $grid.elems;
    my $cols = $grid[0].elems;

    for -1..1 -> $di {
        for -1..1 -> $dj {
            if $di != 0 || $dj != 0 {
                my $ni = $i + $di;
                my $nj = $j + $dj;

                # Check if the neighbor is within grid bounds
                if $ni >= 0 && $ni < $rows && $nj >= 0 && $nj < $cols {
                    $neighbors += ($grid[$ni][$nj] == $id) ?? 1 !! 0;
                }
            }
        }
    }
    return $neighbors;
}

#`[[
    Evolve the grid one generation at a time
]]
sub gol_evolve(@grid) {
    my $rows = @grid.elems;
    my $cols = @grid[0].elems;
    my @new-grid;

    for 0 ..^ $rows -> $i {
        @new-grid[$i] = [];
        for 0 ..^ $cols -> $j {
            my $neighbors1 = gol_neighbors(@grid, $i, $j, 1);
            my $neighbors2 = gol_neighbors(@grid, $i, $j, 2);

            # Decide which life form survives
            if $neighbors1 == 3 {
                @new-grid[$i][$j] = 1;
            } elsif $neighbors2 == 3 {
                @new-grid[$i][$j] = 2;
            } elsif $neighbors1 == 2 || $neighbors2 == 2 {
                @new-grid[$i][$j] = @grid[$i][$j];
            } else {
                @new-grid[$i][$j] = 0;
            }
        }
    }

    return @new-grid;
}

#`[[
    Calculate the final score between the life forms
]]
sub gol_calculate-score(@grid) {
    my $score_1 = 0;
    my $score_2 = 0;
    for @grid.kv -> $i, $row {
        for $row.kv -> $j, $cell {
            $score_1 += ($cell == 1) ?? 1 !! 0;
            $score_2 += ($cell == 2) ?? 1 !! 0;
        }
    }
    return $score_1, $score_2;
}

constant $RED    = 31;
constant $GREEN  = 32;
constant $YELLOW = 33;
constant $BLUE   = 34;

sub gol_encode-ansi-color($color, $text) {
    return "\e[{$color}m{$text}\e[0m";
}

#`[[
    Parse the command line arguments
]]
sub gol_parse-args() {
    my $i = 0;
    while $i < @*ARGS {
        my $arg = @*ARGS[$i];
        if $arg ~~ / '.json' $ / {
            say "Parsing data... $arg";
            @grid = gol_parse-json($arg);
        } elsif $arg ~~ / '.mid' $ / {
            $midi-file = $arg;
        } elsif $arg eq "--no-midi" {
            $no-midi = True;
        } elsif $arg eq "--sleep" {
            $i++;
            if $i < @*ARGS && @*ARGS[$i] ~~ /^\d+$/ {
                $sleep-time = @*ARGS[$i].Int;
            } else {
                die "Expected numeric value after --sleep";
            }
        } elsif $arg eq "--scale" {
            $i++;
            if $i < @*ARGS {
                if @*ARGS[$i] ~~ /^\d+$/ {
                    $scale-offset = @*ARGS[$i].Int;
                } elsif @*ARGS[$i] ~~ /^\w+$/ {
                    $scale-offset = %scale-letter-to-offset{@*ARGS[$i]};
                } else {
                    die "Expected numeric or scale letter after --scale";
                }
            }
        } elsif $arg eq "-h" || $arg eq "--help" {
            say "Usage: $0 [--scale <scale offset / letter>] [--sleep <seconds>] [<midi-output-file>/--no-midi] <json-file>";
            exit;
        }
        $i++;
    }

    # defer saving the midi file when the program exits
    signal(SIGINT).tap({
        say "Exiting...";
        $song.add-track($track.render);
        spurt $midi-file, $song.render;
        exit;
    }) unless $no-midi;
}

sub gol_loop() {
    my @prev-grid = @grid;

    print "\e[2J";         # Clear the screen
    loop {
        print "\e[H";      # Move cursor to (0,0)

        for @grid.kv -> $i, $row {

            my $line = "";
            for $row.kv -> $j, $cell {
                if $cell == 1 && !@prev-grid[$i][$j] {
                    $line ~= gol_encode-ansi-color($RED, "#");
                } elsif $cell == 1 && @prev-grid[$i][$j] {
                    $line ~= gol_encode-ansi-color($GREEN, "#");
                } elsif $cell == 2 && !@prev-grid[$i][$j] {
                    $line ~= gol_encode-ansi-color($BLUE, "@");
                } elsif $cell == 2 && @prev-grid[$i][$j] {
                    $line ~= gol_encode-ansi-color($YELLOW, "@");
                } else {
                    $line ~= " ";
                }
            }
            say $line;
        }

        say "-" x @grid[0].elems;
        gol_grid-append-to-midi(@grid) unless $no-midi;

        say "Generation: $generation";
        if @grid eq @prev-grid and $generation > 0 and $generation % 2 == 0 {
            say "Reached equilibrium at generation $generation";
            my ($score_1, $score_2) = gol_calculate-score(@grid);
            say "Final score: " ~ gol_encode-ansi-color($GREEN, $score_1) ~ " : "
                                ~ gol_encode-ansi-color($YELLOW, $score_2);
            $song.add-track($track.render) unless $no-midi;
            spurt $midi-file, $song.render unless $no-midi;
            last;
        }

        # Todo: also check for 3-step (and more) stable patterns
        if ($generation % 2) == 0 {
            @prev-grid = @grid;
        }

        @grid = gol_evolve(@grid);
        $generation++;

        sleep $sleep-time;
    }
}

#`[[
    Initialize and start the Game of Life loop
]]
# Generate a random grid
@grid = gol_grid(60, 100, 15);

gol_parse-args();
gol_loop();
