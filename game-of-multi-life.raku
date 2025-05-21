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
my $midi-file = "midi/gol-output.mid";
my $no-midi = False;
my $base-octave = 4;
my $song = MIDI::Make::Song.new(:PPQ(96), :format(0));
my $track = MIDI::Make::Track.new;
$track.tempo: ♩174;

#`[[
    Append the current grid state to the midi file
]]
sub gol_grid-append-to-midi(@grid) {
    my $velocity = 64;
    my $note-length = 48;

    sub scale-note(Int $i --> UInt) {
        my %note-map = (
            C => 0,  Cs => 1,  D => 2,  Ds => 3,
            E => 4,  F  => 5,  Fs => 6, G => 7,
            Gs => 8, A  => 9,  As => 10, B => 11
        );
        my @scale = <A B C D E F G>;
        my $max-octave-increment = 5;  # max octave offset from base octave

        my $note-name = @scale[$i % @scale.elems];
        my $octave-increment = ($i div 12);

        $octave-increment = $max-octave-increment if $octave-increment > $max-octave-increment;

        my $octave = $base-octave + $octave-increment;
        my $midi-note = (%note-map{$note-name} + 12 * $octave).UInt;

        return $midi-note min 127;
    }

    # Transform the grid into a list of unique notes
    my %seen;
    my @notes = gather for @grid.kv -> $row-idx, @row {
        for @row.kv -> $col-idx, $v {
            # Take the note according to the row index
            if $v {
                my $scaled-note = scale-note($row-idx % 127);
                take $scaled-note unless %seen{$scaled-note};
                %seen{$scaled-note} = True;
            }
        }
    }

    if @notes {
        my $strum-length = ($note-length / @notes.elems).UInt;
        for @notes -> UInt $note {
            $track.note-on($note, $velocity);
            $track.delta-time($strum-length);
        }

        $track.delta-time(2 * $strum-length);

        for @notes -> UInt $note {
            $track.note-off($note, 0);
        }
    } else {
        # Silence
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

constant $RED = 31;
constant $GREEN = 32;
constant $YELLOW = 33;
constant $BLUE = 34;

sub gol_encode-ansi-color($color, $text) {
    return "\e[{$color}m{$text}\e[0m";
}

#`[[
    Parse the command line arguments
]]
sub gol_parse-args() {
    for @*ARGS -> $arg {
        if $arg ~~ / '.json' $ / {
            # Parse the json grid if provided
            say "Parsing data... $arg";
            @grid = gol_parse-json($arg);
        } elsif $arg ~~ / '.mid' $ / {
            $midi-file = $arg;
        } elsif $arg eq "--no-midi" {
            $no-midi = True;
        }
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
    my $generation = 0;

    print "\e[2J";         # Clear the screen
    loop {
        print "\e[H";      # Move cursor to (0,0)

        @grid = gol_evolve(@grid);
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
        if @grid eq @prev-grid and $generation % 2 == 0 {
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
        $generation++;
        sleep 0.04;
    }
}

#`[[
    Initialize and start the Game of Life loop
]]
# Generate a random grid
@grid = gol_grid(60, 100, 15);

gol_parse-args();
gol_loop();