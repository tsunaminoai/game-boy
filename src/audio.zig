const std = @import("std");
const rl = @import("raylib");
const Game = @import("game.zig");

const gbAudio = @import("game-boy").Audio;

const Audio = @This();

/// The size of the Fast Fourier Transform (FFT) used for audio processing.
const FFTSize = 512;

/// The number of samples processed per audio update.
const SamplesPerUpdate = FFTSize * 4;

/// The size of the buffer used for audio streaming.
const StreamBufferSize = 1024;

/// The sample rate of the audio.
const SampleRate = 44100.0;

/// The duration of each audio sample.
const SampleDuration = 1.0 / SampleRate;

/// Represents the audio signal buffer.
signal: [StreamBufferSize]f32,

/// Represents the duration of each audio frame.
frame_duration: i64,

/// Represents a pointer to the game state.
game_state: *Game,

muted: bool = true,

var osc = Oscillator.Sine(); // default oscillator

/// Initializes the audio system.
///
/// This function creates and returns an `Audio` struct with the specified game state.
/// Example usage:
///   var audio = Audio.init(self);
///   var thread = std.Thread.spawn(
///     .{},
///     Audio.processor,
///     .{&audio},
///   ) catch @panic("Failed to spawn audio processor");
///   thread.detach();
pub fn init(game: *Game) Audio {
    return .{
        .signal = undefined,
        .frame_duration = 0,
        .game_state = game,
    };
}
/// The audio processor function that handles audio streaming and signal generation.
/// Expected to be run in a separate thread.
///
/// This function initializes the audio device, sets the audio stream buffer size,
/// loads the audio stream, sets the volume, and plays the audio stream.
/// It then enters a loop where it checks the game state and adjusts the oscillator amplitude accordingly.
/// Finally, it calls the `streamHandle` function to process the audio stream.
pub fn processor(self: *Audio) !void {
    std.debug.print("Spawning audio processor\n", .{});

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setAudioStreamBufferSizeDefault(StreamBufferSize);

    const stream = rl.loadAudioStream(
        SampleRate,
        8 * @sizeOf(f32),
        1,
    );
    rl.setAudioStreamVolume(stream, 0.5);
    rl.playAudioStream(stream);

    @memset(&self.signal, 0);

    while (true) {
        // if (self.game_state.chip.st > 0) osc.amp = 0.1 else osc.amp = 0.0;
        self.streamHandle(stream);
    }
}

/// Handles the audio stream.
///
/// This function is responsible for processing the audio stream and updating the oscillator.
/// It clears the signal buffer, updates the oscillator for each sample in the buffer,
/// applies the wave shape to the oscillator, and updates the audio stream with the resulting signal.
///
/// # Parameters
/// - `self`: A pointer to the `Audio` struct.
/// - `stream`: The audio stream to be processed.
///
/// # Safety
/// This function assumes that the `Audio` struct is properly initialized and that the `stream` is valid.
pub fn streamHandle(self: *Audio, stream: rl.AudioStream) void {
    if (rl.isAudioStreamProcessed(stream)) {
        @memset(&self.signal, 0);

        const start_time = std.time.microTimestamp();

        // update oscillator

        for (0..StreamBufferSize) |i| {
            osc.update(440.0);
            self.signal[i] += std.math.clamp(
                osc.waveShape(osc),
                -0xFF,
                0xFF,
            ) * if (self.muted) 0 else osc.amp;
        }

        rl.updateAudioStream(stream, &self.signal, self.signal.len);
        self.frame_duration = std.time.microTimestamp() - start_time;
    }
}

pub fn mute(self: *Audio) void {
    self.muted = !self.muted;
}

const Oscillator = struct {
    phase: f32 = 0,
    delta: f32 = 0,
    freq: f32 = 0,
    amp: f32 = 0.1,

    waveShape: *const fn (@This()) f32,

    /// Updates the oscillator's phase based on the frequency and modulator.
    ///
    /// The phase is incremented by the frequency plus the modulator multiplied by `SampleDuration`.
    /// If the phase exceeds 1.0, it wraps around to 0.0.
    /// If the phase is less than 0.0, it wraps around to 1.0.
    ///
    /// # Parameters
    ///
    /// - `modulator`: The modulator value to be added to the frequency.
    ///
    pub fn update(self: *Oscillator, modulator: f32) void {
        self.delta = self.freq + modulator * SampleDuration;
        self.phase += self.delta;
        if (self.phase >= 1.0) self.phase -= 1.0;
        if (self.phase < 0.0) self.phase += 1.0;
    }

    /// Returns the sine wave value at the current phase.
    ///
    /// The sine wave value is calculated using the formula `sin(2.0 * pi * phase)`.
    ///
    /// # Returns
    ///
    /// The sine wave value at the current phase.
    ///
    pub fn sine(self: Oscillator) f32 {
        return @sin(2.0 * std.math.pi * self.phase);
    }

    /// Creates a new oscillator with the sine wave shape.
    ///
    /// # Returns
    ///
    /// A new oscillator with the sine wave shape.
    ///
    pub fn Sine() Oscillator {
        return .{
            .waveShape = Oscillator.sine,
        };
    }
};
