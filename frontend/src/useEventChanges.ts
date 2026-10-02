import { createConsumer } from "@rails/actioncable";
import { useEffect, useRef } from "react";

const consumer = createConsumer("/cable");

// Calls onChange (debounced) whenever the hub says the event changed.
export function useEventChanges(eventId: string, onChange: () => void): void {
  const latest = useRef(onChange);
  latest.current = onChange;

  useEffect(() => {
    let timer: number | undefined;
    const subscription = consumer.subscriptions.create(
      { channel: "EventChannel", event_id: eventId },
      {
        received() {
          window.clearTimeout(timer);
          timer = window.setTimeout(() => latest.current(), 300);
        },
      },
    );
    return () => {
      window.clearTimeout(timer);
      subscription.unsubscribe();
    };
  }, [eventId]);
}
