#!/usr/bin/env raku
#`<<
    A GoL in Raku
    Written by: Amplee
    Date: 2025-05-19
>>

use JSON::Fast;

sub game-of-life_parse-json($json-path) {
    return from-json slurp($json-path);
}

#`[[
    Generate a grid of size $m x $n with $population % of cells alive
]]
sub game-of-life_grid($m, $n, $population) {
    my @grid;
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
sub game-of-life_neighbors($grid, $i, $j, $id) {
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
sub game-of-life_evolve(@grid) {
    my $rows = @grid.elems;
    my $cols = @grid[0].elems;
    my @new-grid;

    for 0 ..^ $rows -> $i {
        @new-grid[$i] = [];
        for 0 ..^ $cols -> $j {
            my $neighbors1 = game-of-life_neighbors(@grid, $i, $j, 1);
            my $neighbors2 = game-of-life_neighbors(@grid, $i, $j, 2);

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

sub calculate-score(@grid) {
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

sub encode-ansi-color($color, $text) {
    return "\e[{$color}m{$text}\e[0m";
}

#`[[
    Initialize and start the Game of Life loop
]]
my @grid;

# Parse the json grid if provided, otherwise generate a random grid
if @*ARGS[0] {
    say "Parsing data... @*ARGS[0]";
    @grid = game-of-life_parse-json(@*ARGS[0]);
} else {
    @grid = game-of-life_grid(60, 100, 10);
}

my @prev-grid = @grid;
my $generation = 0;

loop {
    # Clear the screen depending on OS
    my $clear-cmd =
        $*DISTRO.name.lc.contains("win") ?? "cls" !! "clear";
    shell($clear-cmd);

    @grid = game-of-life_evolve(@grid);
    for @grid.kv -> $i, $row {

        my $line = "";
        for $row.kv -> $j, $cell {
            if $cell == 1 && !@prev-grid[$i][$j] {
                $line ~= encode-ansi-color($RED, "#");
            } elsif $cell == 1 && @prev-grid[$i][$j] {
                $line ~= encode-ansi-color($GREEN, "#");
            } elsif $cell == 2 && !@prev-grid[$i][$j] {
                $line ~= encode-ansi-color($BLUE, "@");
            } elsif $cell == 2 && @prev-grid[$i][$j] {
                $line ~= encode-ansi-color($YELLOW, "@");
            } else {
                $line ~= " ";
            }
        }
        say $line;
    }
 
    say "-" x @grid[0].elems;

    say "Generation: $generation";
    if @grid eq @prev-grid and $generation % 2 == 0 {
        say "Reached equilibrium at generation $generation";
        my ($score_1, $score_2) = calculate-score(@grid);
        say "Final score: " ~ encode-ansi-color($GREEN, $score_1) ~ " : "
                            ~ encode-ansi-color($YELLOW, $score_2);
        last;
    }

    # Todo: also check for 3-step (and more) stable patterns
    if ($generation % 2) == 0 {
        @prev-grid = @grid;
    }
    $generation++;
    sleep 0.1;
}
