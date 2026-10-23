// NanoMig-style Verilator runner for the stable core, SDRAM, SD and Companion image BFM.
#include "Vminimig_tb.h"
#include "sd_card_config.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <SDL.h>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <memory>
#include <string>
#include <utility>
#include <vector>

Vminimig_tb *tb;
double simulation_time = 0;
char *sector_string(int, uint32_t) {
  static char empty[] = "";
  return empty;
}

static void screenshot(const std::string &path, const std::vector<uint32_t> &pixels, int width, int height) {
  std::ofstream out(path, std::ios::binary);
  out << "P6\n" << width << " " << height << "\n255\n";
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      uint32_t pixel = pixels[y * 2048 + x];
      out.put(pixel >> 16);
      out.put(pixel >> 8);
      out.put(pixel);
    }
  }
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  double seconds = 0.2;
  bool smoke = false, window = false;
  const char *trace_path = nullptr;
  std::string picture;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--seconds" && i + 1 < argc)
      seconds = std::stod(argv[++i]);
    else if (arg == "--rom" && i + 1 < argc)
      rom_image[0] = argv[++i];
    else if (arg == "--trace" && i + 1 < argc)
      trace_path = argv[++i];
    else if (arg == "--screenshot" && i + 1 < argc)
      picture = argv[++i];
    else if (arg == "--window")
      window = true;
    else if (arg == "--smoke")
      smoke = true;
    else if (arg.rfind("--df", 0) == 0 && arg.size() == 5 && i + 1 < argc) {
      int drive = arg[4] - '0';
      if (drive < 0 || drive > 3)
        return 2;
      file_image[drive] = argv[++i];
    } else if (arg.rfind("--dh", 0) == 0 && arg.size() == 5 && i + 1 < argc) {
      int drive = arg[4] - '0';
      if (drive < 0 || drive > 1)
        return 2;
      file_image[4 + drive] = argv[++i];
    } else {
      std::fprintf(stderr, "Unknown/incomplete argument: %s\n", argv[i]);
      return 2;
    }
  }
  if (!rom_image[0]) {
    std::fprintf(stderr, "A 256/512 KiB ROM is required: --rom path\n");
    return 2;
  }
  auto model = std::make_unique<Vminimig_tb>();
  tb = model.get();
  std::unique_ptr<VerilatedFstC> trace;
  if (trace_path) {
    Verilated::traceEverOn(true);
    trace = std::make_unique<VerilatedFstC>();
    tb->trace(trace.get(), 3);
    trace->open(trace_path);
  }
  tb->clk114 = 0;
  tb->por = 1;
  tb->reset = 1;
  tb->memory_config = std::getenv("MEMORY") ? std::strtoul(std::getenv("MEMORY"), nullptr, 0) : 0x15;
  tb->cpu_config = std::getenv("CPU") ? std::strtoul(std::getenv("CPU"), nullptr, 0) : 0;
  tb->chipset_config = std::getenv("CHIPSET") ? std::strtoul(std::getenv("CHIPSET"), nullptr, 0) : 0;
  tb->floppy_config = 0x5;
  tb->ide_config = (file_image[4] || file_image[5]) ? 7 : 0;
  tb->kms_data = 0;
  tb->kms_type = 0;
  tb->kms_level = 0;
  tb->mouse_buttons = 0;
  sd_init();
  std::vector<uint32_t> pixels(2048 * 1024, 0);
  int x = 0, y = 0, width = 1820, height = 312, frames = 0;
  std::deque<std::pair<uint8_t, uint8_t>> input_queue;
  int input_cooldown = 0;
  bool old_hs = true, old_vs = true, old_clk28 = false, quit = false;
  SDL_Window *display = nullptr;
  SDL_Renderer *renderer = nullptr;
  SDL_Texture *texture = nullptr;
  if (window) {
    if (SDL_Init(SDL_INIT_VIDEO))
      return 2;
    display = SDL_CreateWindow("MiniMig MiSTle", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 908, 626, 0);
    renderer = SDL_CreateRenderer(display, -1, 0);
    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 2048, 1024);
  }
  constexpr double half_tick = 0.5 / 114285714.28571428;
  uint64_t ticks = 0;
  bool passed = false;
  int debug_count = 0;
  bool last_ack = true;
  while (!Verilated::gotFinish() && !quit && simulation_time < seconds) {
    tb->clk114 = !tb->clk114;
    tb->por = simulation_time < 0.00001;
    tb->reset = simulation_time < 0.00008;
    tb->eval();
    if (tb->clk28 && !old_clk28) {
      sd_handle();
      if (input_cooldown)
        --input_cooldown;
      else if (!input_queue.empty()) {
        const auto event = input_queue.front();
        input_queue.pop_front();
        tb->kms_type = event.first;
        tb->kms_data = event.second;
        tb->kms_level = !tb->kms_level;
        input_cooldown = 8;
      }
      if (x < 2048 && y < 1024)
        pixels[y * 2048 + x] = 0xff000000 | (tb->red << 16) | (tb->green << 8) | tb->blue;
      ++x;
      if (tb->hs_n && !old_hs) {
        if (x > 100 && x <= 2048)
          width = x;
        x = 0;
        ++y;
        if (!tb->vs_n && old_vs) {
          if (y > 100 && y <= 1024)
            height = y;
          y = 0;
          ++frames;
          if (window) {
            SDL_UpdateTexture(texture, nullptr, pixels.data(), 2048 * 4);
            SDL_Rect source{0, 0, width, height};
            SDL_RenderCopy(renderer, texture, &source, nullptr);
            SDL_RenderPresent(renderer);
            SDL_Event event;
            while (SDL_PollEvent(&event)) {
              if (event.type == SDL_QUIT)
                quit = true;
              // USB HID usage codes follow SDL scancodes. Use the core's stable Amiga keymap below.
              if ((event.type == SDL_KEYDOWN && !event.key.repeat) || event.type == SDL_KEYUP) {
                input_queue.emplace_back(2, (event.type == SDL_KEYUP ? 0x80 : 0) | (event.key.keysym.scancode & 0x7f));
              }
              if (event.type == SDL_MOUSEMOTION) {
                int dx = event.motion.xrel, dy = event.motion.yrel;
                while (dx || dy) {
                  int xstep = std::clamp(dx, -127, 127), ystep = std::clamp(dy, -127, 127);
                  if (xstep)
                    input_queue.emplace_back(0, uint8_t(xstep));
                  if (ystep)
                    input_queue.emplace_back(1, uint8_t(ystep));
                  dx -= xstep;
                  dy -= ystep;
                }
              }
              if (event.type == SDL_MOUSEBUTTONDOWN || event.type == SDL_MOUSEBUTTONUP) {
                int bit = event.button.button == SDL_BUTTON_LEFT ? 1 : event.button.button == SDL_BUTTON_RIGHT ? 2 : 4;
                if (event.type == SDL_MOUSEBUTTONDOWN)
                  tb->mouse_buttons |= bit;
                else
                  tb->mouse_buttons &= ~bit;
              }
            }
          }
        }
        old_vs = tb->vs_n;
      }
      old_hs = tb->hs_n;
    }
    if (std::getenv("SIM_DEBUG") && tb->rom_ready && !tb->debug_as && !tb->debug_dtack && last_ack &&
        debug_count++ < 32)
      std::printf("CPU %.6f ms addr=%08x data=%04x\n", simulation_time * 1000, tb->debug_cpu_addr, tb->debug_cpu_data);
    last_ack = tb->debug_dtack;
    old_clk28 = tb->clk28;
    if (trace)
      trace->dump(++ticks);
    else
      ++ticks;
    simulation_time += half_tick;
    if (smoke && tb->smoke_pass) {
      passed = true;
      break;
    }
  }
  if (!picture.empty())
    screenshot(picture, pixels, width, height);
  std::printf("Simulation: %.3f ms, %d frames, ROM ready=%d, smoke=%s\n", simulation_time * 1000, frames, tb->rom_ready,
              passed ? "PASS" : "not reached");
  std::printf("CPU address=%08x reset_n=%d ROM vectors=%016llx\n", tb->debug_cpu_addr, tb->debug_cpu_reset,
              (unsigned long long)tb->debug_rom);
  if (trace)
    trace->close();
  tb->final();
  if (window) {
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(display);
    SDL_Quit();
  }
  return smoke && !passed ? 1 : 0;
}
// vim: ts=2 sw=2 tw=120 et
