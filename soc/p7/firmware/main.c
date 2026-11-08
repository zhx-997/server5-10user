#include "kwt_v43_streams.h"

extern uint32_t cross_lane_test(void);
extern uint32_t misaligned_load_test(void);

static uint32_t memory_and_fetch_test(void) {
    for (unsigned bank = 0; bank < 8; ++bank) {
        volatile uint32_t *itcm = (volatile uint32_t *)(0x80006000u + bank * 32768u);
        volatile uint32_t *dtcm = (volatile uint32_t *)(0x90000100u + bank * 32768u);
        *itcm = 0x12345600u + bank;
        *dtcm = 0xabcdef00u + bank;
    }
    for (unsigned bank = 0; bank < 8; ++bank) {
        volatile uint32_t *itcm = (volatile uint32_t *)(0x80006000u + bank * 32768u);
        volatile uint32_t *dtcm = (volatile uint32_t *)(0x90000100u + bank * 32768u);
        if (*itcm != 0x12345600u + bank) return 0x100u + bank;
        if (*dtcm != 0xabcdef00u + bank) return 0x200u + bank;
        ((volatile uint8_t *)itcm)[1] = 0xa5;
        ((volatile uint16_t *)dtcm)[1] = 0x5a6b;
        if (*itcm != 0x1234a500u + bank) return 0x300u + bank;
        if (*dtcm != 0x5a6bef00u + bank) return 0x400u + bank;
    }
    if (cross_lane_test() != 128) return 0x501;
    volatile uint32_t *code = (volatile uint32_t *)0x80020000u;
    uint32_t (*entry)(void) = (uint32_t (*)(void))0x80020000u;
    code[0] = 0x02a00513;
    code[1] = 0x00008067;
    __asm__ volatile ("fence.i" ::: "memory");
    if (entry() != 42) return 0x502;
    code[0] = 0x00700513;
    __asm__ volatile ("fence.i" ::: "memory");
    if (entry() != 7) return 0x503;
    return 0;
}

int main(void) {
    volatile uint32_t *mailbox = (volatile uint32_t *)0xa0000000u;
    volatile kwt_descriptor *slot = (volatile kwt_descriptor *)0xa0000200u;
    uint32_t completed = 0;
    mailbox[1] = 0;
    mailbox[2] = 0;
    mailbox[3] = 0;
    mailbox[4] = 0;
    mailbox[6] = memory_and_fetch_test();
    if (mailbox[6] != 0) for (;;) { }
    mailbox[14] = 0;
    if (misaligned_load_test() != 0x204 || mailbox[14] != 1) {
        mailbox[6] = 0x602;
        for (;;) { }
    }
    mailbox[15] = 0;
    __asm__ volatile ("csrs mie, %0\ncsrs mstatus, %0" :: "r"(8u) : "memory");
    *(volatile uint32_t *)0x02000000u = 1;
    for (unsigned wait = 0; wait < 100000 && mailbox[15] == 0; ++wait) { }
    __asm__ volatile ("csrc mstatus, %0\ncsrc mie, %0" :: "r"(8u) : "memory");
    if (mailbox[15] != 1) {
        mailbox[6] = 0x601;
        for (;;) { }
    }
    mailbox[7] = 0x20300001u;
    for (;;) {
        uint32_t ticket = mailbox[0];
        if (ticket == 0 || ticket == completed) continue;
        __asm__ volatile ("fence rw,rw" ::: "memory");
        unsigned layer = mailbox[8];
        kwt_descriptor descriptor;
        uint32_t status = KWT_BAD_LAYER;
        if (layer < KWT_LAYERS) {
            if (kwt_make_streams_descriptor(&descriptor, layer, mailbox[9],
                    mailbox[10], mailbox[11], mailbox[12], &kwt_v42_profiles[layer]) == 0) {
                *slot = descriptor;
                status = kwt_run(slot);
                if (status == KWT_OK)
                    mailbox[5] = *(volatile uint32_t *)(uintptr_t)mailbox[12];
            }
        }
        mailbox[2] = status;
        __asm__ volatile ("fence rw,rw" ::: "memory");
        mailbox[1] = ticket;
        completed = ticket;
    }
}
